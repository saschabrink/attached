defmodule Attached.Originals.PurgeOrphansWorkerTest do
  use Attached.DataCase, async: false
  use Oban.Testing, repo: Attached.TestRepo

  import Ecto.Query

  alias Attached.Originals
  alias Attached.Originals.Original
  alias Attached.Originals.PurgeOrphansWorker

  defp insert_orphan!(attrs \\ []) do
    %{
      key: "k-#{System.unique_integer([:positive])}",
      filename: "f.txt",
      content_type: "text/plain",
      byte_size: 42,
      checksum: "chk",
      storage_backend: "Attached.StorageBackends.Disk",
      owner_table: "users",
      owner_field: "avatar_attached_original_id"
    }
    |> Map.merge(Map.new(attrs))
    |> Original.changeset()
    |> Repo.insert!()
  end

  defp backdate!(%Original{id: id}, seconds) do
    cutoff = DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)

    {1, _} =
      Repo.update_all(from(b in Original, where: b.id == ^id), set: [inserted_at: cutoff])

    :ok
  end

  describe "grace period" do
    test "fresh orphans survive the sweep" do
      orphan = insert_orphan!()

      assert :ok = perform_job(PurgeOrphansWorker, %{})
      assert Originals.get(orphan.id)
    end

    test "orphans older than the grace period are purged" do
      old = insert_orphan!()
      fresh = insert_orphan!()
      backdate!(old, 3 * 86_400)

      assert :ok = perform_job(PurgeOrphansWorker, %{})

      refute Originals.get(old.id)
      assert Originals.get(fresh.id)
    end

    test "orphan_grace_period: 0 purges regardless of age" do
      Application.put_env(:attached, :orphan_grace_period, 0)
      on_exit(fn -> Application.delete_env(:attached, :orphan_grace_period) end)

      orphan = insert_orphan!()

      assert :ok = perform_job(PurgeOrphansWorker, %{})
      refute Originals.get(orphan.id)
    end
  end

  describe "purge_by_owner_group/2" do
    test "only enqueues purges for orphans past the grace period" do
      old = insert_orphan!()
      _fresh = insert_orphan!()
      backdate!(old, 3 * 86_400)

      Originals.purge_by_owner_group("users", "avatar_attached_original_id")

      assert [job] = all_enqueued(worker: Attached.Originals.PurgeWorker)
      assert job.args["original_id"] == old.id
    end
  end
end
