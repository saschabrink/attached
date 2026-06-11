defmodule AttachedTest do
  use Attached.DataCase, async: false
  use Oban.Testing, repo: Attached.TestRepo

  alias Attached.Test.User

  setup do
    tmp_path =
      Path.join(System.tmp_dir!(), "attached_test_#{System.unique_integer([:positive])}.txt")

    File.write!(tmp_path, "hello world")
    on_exit(fn -> File.rm(tmp_path) end)

    {:ok, upload: %{path: tmp_path, filename: "test.txt", content_type: "text/plain"}}
  end

  describe "put_attached/3 with attached" do
    test "attaches a file via changeset", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      assert user.avatar_attached_original_id != nil

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      assert original.filename == "test.txt"
      assert original.content_type == "text/plain"
      assert original.byte_size == 11
      assert original.owner_table == "users"
      assert original.owner_field == "avatar_attached_original_id"
      assert original.checksum != nil
      assert original.key != nil
      assert original.storage_backend == "local"
      assert_enqueued(worker: Attached.Originals.ExtractMetadataWorker, args: %{original_id: original.id})
    end

    test "uploads the file to the storage service", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      assert Attached.StorageBackends.exists?(original.key)

      {:ok, data} = Attached.StorageBackends.download(original.key)
      assert data == "hello world"
    end

    test "nil upload is a no-op", _ctx do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, nil)
        |> Repo.insert!()

      assert user.avatar_attached_original_id == nil
    end

    test "re-attaches an existing original without re-uploading", %{upload: upload} do
      user1 =
        User.changeset(%User{}, %{name: "User1"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user1.avatar_attached_original_id)

      user2 =
        User.changeset(%User{}, %{name: "User2"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, original)
        |> Repo.insert!()

      assert user2.avatar_attached_original_id == original.id
    end

    test "overwrites the attachment even when no other fields change", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      first_original_id = user.avatar_attached_original_id

      new_upload = %{
        path: upload.path,
        filename: "new.txt",
        content_type: "text/plain"
      }

      updated_user =
        User.changeset(user, %{})
        |> Attached.Ecto.Changeset.put_attached(:avatar, new_upload)
        |> Repo.update!()

      assert updated_user.avatar_attached_original_id != nil
      assert updated_user.avatar_attached_original_id != first_original_id

      new_original = Repo.get!(Attached.Originals.Original, updated_user.avatar_attached_original_id)
      assert new_original.filename == "new.txt"
    end

    test "raises on an unknown field" do
      assert_raise ArgumentError, ~r/does not have an attached field/, fn ->
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:nonexistent, %{path: "/tmp/x", filename: "x"})
      end
    end

    test "detects real content type from magic bytes, overriding caller-supplied type" do
      png_path = Path.expand("support/fixtures/header.png", __DIR__)
      upload = %{path: png_path, filename: "photo.png", content_type: "application/octet-stream"}

      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      assert original.content_type == "image/png"
    end

    test "skips content-type detection when identify_content_type: false" do
      Application.put_env(:attached, :identify_content_type, false)
      on_exit(fn -> Application.delete_env(:attached, :identify_content_type) end)

      png_path = Path.expand("support/fixtures/header.png", __DIR__)
      upload = %{path: png_path, filename: "photo.png", content_type: "application/octet-stream"}

      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      assert original.content_type == "application/octet-stream"
    end
  end

  describe "put_attached/3 imported via use Attached.Ecto.Schema" do
    test "works inside the schema's own changeset", %{upload: upload} do
      user =
        User.changeset_with_avatar(%User{}, %{name: "Test", avatar: upload})
        |> Repo.insert!()

      assert user.avatar_attached_original_id != nil
    end
  end

  describe "attached?/2" do
    test "returns false when nothing is attached" do
      user = Repo.insert!(User.changeset(%User{}, %{name: "Test"}))
      refute Attached.attached?(user, :avatar)
    end

    test "returns true when a file is attached", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      assert Attached.attached?(user, :avatar)
    end

    test "raises for an unknown field" do
      user = Repo.insert!(User.changeset(%User{}, %{name: "Test"}))

      assert_raise ArgumentError, ~r/does not have an attached field :avatarr/, fn ->
        Attached.attached?(user, :avatarr)
      end
    end

    test "raises for a schema without attached fields" do
      assert_raise ArgumentError, ~r/does not use Attached.Ecto.Schema/, fn ->
        Attached.attached?(%URI{}, :avatar)
      end
    end
  end

  describe "url/2" do
    test "returns a URL for the original", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      assert Attached.url(user, :avatar) =~ "/attachments/originals/"
    end

    test "returns nil when nothing is attached" do
      user =
        Repo.insert!(User.changeset(%User{}, %{name: "Test"}))
        |> Repo.preload(avatar_attached_original: :variants)

      assert Attached.url(user, :avatar) == nil
    end

    test "raises for an unknown field instead of returning nil" do
      user = Repo.insert!(User.changeset(%User{}, %{name: "Test"}))

      assert_raise ArgumentError, ~r/does not have an attached field :avatarr/, fn ->
        Attached.url(user, :avatarr)
      end
    end
  end

  describe "url/3 with a named variant" do
    test "processes variant synchronously and returns a URL", %{upload: _upload} do
      png_path = Path.expand("support/fixtures/header.png", __DIR__)
      image_upload = %{path: png_path, filename: "photo.png", content_type: "image/png"}

      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, image_upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      url = Attached.url(user, :avatar, :thumb)
      assert url =~ "/attachments/originals/"
      token = url |> String.split("/originals/") |> List.last()
      assert {:ok, path} = Attached.Web.Signer.verify(token)
      assert Attached.StorageBackends.exists?(path)

      variant = Attached.Variants.get_by_path(path)
      assert variant.name == "thumb"
    end

    test "caches the variant on subsequent calls", %{upload: _upload} do
      png_path = Path.expand("support/fixtures/header.png", __DIR__)
      image_upload = %{path: png_path, filename: "photo.png", content_type: "image/png"}

      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, image_upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      url1 = Attached.url(user, :avatar, :thumb)
      user = Repo.preload(user, [avatar_attached_original: :variants], force: true)
      url2 = Attached.url(user, :avatar, :thumb)
      assert url1 == url2
    end

    test "raises a helpful error when :variants is not preloaded", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(:avatar_attached_original)

      assert_raise ArgumentError, ~r/:variants to be preloaded/, fn ->
        Attached.url(user, :avatar, :thumb)
      end
    end

    test "raises on an unknown variant", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      assert_raise ArgumentError, ~r/Unknown variant/, fn ->
        Attached.url(user, :avatar, :nonexistent)
      end
    end
  end

  describe "with_attached/2" do
    test "preloads the original for attached", %{upload: upload} do
      User.changeset(%User{}, %{name: "Test"})
      |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
      |> Repo.insert!()

      [user] = User |> Attached.with_attached(:avatar) |> Repo.all()
      assert %Attached.Originals.Original{} = user.avatar_attached_original
    end
  end

  describe "Originals.purge_later/1" do
    test "enqueues a purge job for the given original ID", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(:avatar_attached_original)

      original_id = user.avatar_attached_original.id
      {:ok, _job} = Attached.Originals.purge_later(original_id)
      assert_enqueued(worker: Attached.Originals.PurgeWorker, args: %{original_id: original_id})
    end
  end

  describe "Originals.extract_metadata_later/1" do
    test "enqueues an extract-metadata job for the given original ID", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(:avatar_attached_original)

      original_id = user.avatar_attached_original.id
      {:ok, _job} = Attached.Originals.extract_metadata_later(original_id)
      assert_enqueued(worker: Attached.Originals.ExtractMetadataWorker, args: %{original_id: original_id})
    end
  end

  describe "Originals.purge_orphans_later/0" do
    test "enqueues a PurgeOrphans job" do
      {:ok, _job} = Attached.Originals.purge_orphans_later()
      assert_enqueued(worker: Attached.Originals.PurgeOrphansWorker)
    end
  end

  describe "Originals orphan queries" do
    import ExUnit.CaptureLog

    defp insert_original!(attrs) do
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
      |> Attached.Originals.Original.changeset()
      |> Repo.insert!()
    end

    test "count_orphans/0 returns 0 when there are no originals" do
      assert Attached.Originals.count_orphans() == 0
    end

    test "count_orphans/0 counts originals whose owner row is gone" do
      insert_original!(byte_size: 100)
      insert_original!(byte_size: 200)
      assert Attached.Originals.count_orphans() == 2
    end

    test "count_orphans/0 ignores originals with a live owner", %{upload: upload} do
      User.changeset(%User{}, %{name: "Live"})
      |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
      |> Repo.insert!()

      assert Attached.Originals.count_orphans() == 0
    end

    test "count_orphans/0 skips groups with an invalid owner_field and logs" do
      insert_original!(owner_field: "nonexistent_column")

      log = capture_log(fn -> assert Attached.Originals.count_orphans() == 0 end)
      assert log =~ "Skipping orphan group users.nonexistent_column"
    end

    test "list_orphan_groups/0 returns aggregated summary per group" do
      insert_original!(byte_size: 100)
      insert_original!(byte_size: 200)

      assert [group] = Attached.Originals.list_orphan_groups()
      assert group.owner_table == "users"
      assert group.owner_field == "avatar_attached_original_id"
      assert group.orphan_count == 2
      assert group.total_bytes == 300
    end

    test "list_orphan_groups/0 omits groups with zero orphans", %{upload: upload} do
      User.changeset(%User{}, %{name: "Live"})
      |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
      |> Repo.insert!()

      assert Attached.Originals.list_orphan_groups() == []
    end

    test "count_orphans/2 scoped to one group" do
      insert_original!([])
      assert Attached.Originals.count_orphans("users", "avatar_attached_original_id") == 1
    end

    test "count_orphans/2 returns 0 for invalid owner_field with log" do
      insert_original!(owner_field: "nonexistent_column")

      log =
        capture_log(fn ->
          assert Attached.Originals.count_orphans("users", "nonexistent_column") == 0
        end)

      assert log =~ "Skipping orphan group users.nonexistent_column"
    end

    test "list_orphans/4 returns orphaned originals for the given group" do
      insert_original!(filename: "orphan.jpg")

      assert [%Attached.Originals.Original{filename: "orphan.jpg"}] =
               Attached.Originals.list_orphans("users", "avatar_attached_original_id")
    end

    test "list_orphans/4 respects limit and offset" do
      for _ <- 1..5, do: insert_original!([])

      page1 = Attached.Originals.list_orphans("users", "avatar_attached_original_id", 3, 0)
      page2 = Attached.Originals.list_orphans("users", "avatar_attached_original_id", 3, 3)

      assert length(page1) == 3
      assert length(page2) == 2
    end

    test "list_orphans/4 returns [] for invalid owner_field" do
      insert_original!(owner_field: "nonexistent_column")

      log =
        capture_log(fn ->
          assert Attached.Originals.list_orphans("users", "nonexistent_column") == []
        end)

      assert log =~ "Skipping orphan group"
    end
  end

  describe "Originals.list/1 with :distinct" do
    defp insert_minimal_original!(attrs) do
      %{
        key: "k-#{System.unique_integer([:positive])}",
        filename: "f.txt",
        content_type: "text/plain",
        byte_size: 1,
        checksum: "c",
        storage_backend: "Attached.StorageBackends.Disk",
        owner_table: "users",
        owner_field: "avatar_attached_original_id"
      }
      |> Map.merge(Map.new(attrs))
      |> Attached.Originals.Original.changeset()
      |> Repo.insert!()
    end

    test "returns distinct values sorted ascending" do
      insert_minimal_original!(storage_backend: "Attached.StorageBackends.Disk")
      insert_minimal_original!(storage_backend: "Attached.StorageBackends.S3")
      insert_minimal_original!(storage_backend: "Attached.StorageBackends.Disk")

      assert Attached.Originals.list(distinct: :storage_backend) == [
               "Attached.StorageBackends.Disk",
               "Attached.StorageBackends.S3"
             ]
    end

    test "honors :query to scope the distinct set" do
      insert_minimal_original!(owner_table: "users")
      insert_minimal_original!(owner_table: "posts")

      import Ecto.Query
      only_users = fn q -> where(q, [b], b.owner_table == "users") end
      assert Attached.Originals.list(distinct: :owner_table, query: only_users) == ["users"]
    end

    test "raises on unsupported option" do
      assert_raise ArgumentError, ~r/:bogus/, fn ->
        Attached.Originals.list(distinct: :storage_backend, bogus: true)
      end
    end
  end

  describe "Originals.get_owner/1" do
    test "returns the owning row as a map", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Owner"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(:avatar_attached_original)

      row = Attached.Originals.get_owner(user.avatar_attached_original)
      assert row.id == user.id
      assert row.name == "Owner"
    end

    test "returns nil when no owner row references the original" do
      original =
        %{
          key: "k-#{System.unique_integer([:positive])}",
          filename: "f.txt",
          content_type: "text/plain",
          byte_size: 1,
          checksum: "c",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "avatar_attached_original_id"
        }
        |> Attached.Originals.Original.changeset()
        |> Repo.insert!()

      assert Attached.Originals.get_owner(original) == nil
    end

    test "returns nil when owner_field is not a real column" do
      original =
        %{
          key: "k-#{System.unique_integer([:positive])}",
          filename: "f.txt",
          content_type: "text/plain",
          byte_size: 1,
          checksum: "c",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "nonexistent_column"
        }
        |> Attached.Originals.Original.changeset()
        |> Repo.insert!()

      assert Attached.Originals.get_owner(original) == nil
    end

    test "returns nil for legacy rows whose owner names are not plain identifiers" do
      # Simulate a row from before ingest-time validation by inserting the
      # struct directly — Repo.insert!/1 on a struct bypasses the changeset.
      original =
        Repo.insert!(%Attached.Originals.Original{
          key: "k-#{System.unique_integer([:positive])}",
          filename: "f.txt",
          content_type: "text/plain",
          byte_size: 1,
          checksum: "c",
          storage_backend: "local",
          owner_table: ~s(users"; DROP TABLE users;--),
          owner_field: "avatar_attached_original_id"
        })

      assert Attached.Originals.get_owner(original) == nil
    end
  end

  describe "Originals.Scopes.orphans/3" do
    test "raises when owner names are not plain SQL identifiers" do
      assert_raise ArgumentError, ~r/owner_table .* not a plain SQL identifier/, fn ->
        Attached.Originals.list(query: &Attached.Originals.Scopes.orphans(&1, ~s(users"; DROP), "avatar_attached_original_id"))
      end

      assert_raise ArgumentError, ~r/owner_field .* not a plain SQL identifier/, fn ->
        Attached.Originals.list(query: &Attached.Originals.Scopes.orphans(&1, "users", "x; --"))
      end
    end
  end

  describe "purge/3" do
    test "deletes the original record and file from storage", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(:avatar_attached_original)

      original = user.avatar_attached_original
      assert Attached.StorageBackends.exists?(original.key)

      Attached.purge(user, :avatar)

      refute Attached.StorageBackends.exists?(original.key)
      assert Repo.get(Attached.Originals.Original, original.id) == nil
    end
  end
end
