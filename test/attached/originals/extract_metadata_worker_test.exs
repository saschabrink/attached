defmodule Attached.Originals.ExtractMetadataWorkerTest do
  use Attached.DataCase, async: false
  use Oban.Testing, repo: Attached.TestRepo

  @fixture_png Path.expand("../../support/fixtures/header.png", __DIR__)
  @analysis_available Code.ensure_loaded?(Vix.Vips.Image) or
                        not is_nil(System.find_executable("identify"))

  defp insert_original(attrs) do
    Attached.Originals.Original.changeset(attrs) |> Repo.insert!()
  end

  describe "perform/1" do
    @tag skip: not @analysis_available
    test "stores image metadata in original.metadata" do
      key = "extract_img_#{System.unique_integer([:positive])}"
      :ok = Attached.StorageBackends.upload(key, @fixture_png)

      original =
        insert_original(%{
          key: key,
          filename: "header.png",
          content_type: "image/png",
          byte_size: File.stat!(@fixture_png).size,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "avatar"
        })

      assert :ok = perform_job(Attached.Originals.ExtractMetadataWorker, %{"original_id" => original.id})

      updated = Repo.get!(Attached.Originals.Original, original.id)
      assert updated.metadata["width"] == 1
      assert updated.metadata["height"] == 1
    end

    test "returns :ok and leaves metadata empty when no extractor matches" do
      key = "extract_noop_#{System.unique_integer([:positive])}"
      tmp = Path.join(System.tmp_dir!(), "extract_noop.bin")
      File.write!(tmp, "no magic bytes match")
      :ok = Attached.StorageBackends.upload(key, tmp)
      File.rm(tmp)

      original =
        insert_original(%{
          key: key,
          filename: "data.bin",
          content_type: "application/octet-stream",
          byte_size: 20,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "avatar"
        })

      assert :ok = perform_job(Attached.Originals.ExtractMetadataWorker, %{"original_id" => original.id})

      updated = Repo.get!(Attached.Originals.Original, original.id)
      assert updated.metadata == %{}
    end
  end
end
