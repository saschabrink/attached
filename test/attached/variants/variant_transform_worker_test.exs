defmodule Attached.Variants.VariantTransformWorkerTest do
  use Attached.DataCase, async: false
  use Oban.Testing, repo: Attached.TestRepo

  alias Attached.Variants
  alias Attached.Variants.Variant

  @ffmpeg_available not is_nil(System.find_executable("ffmpeg"))
  @image_tool_available not is_nil(System.find_executable("identify")) or
                          Code.ensure_loaded?(Vix.Vips.Image)

  defp insert_original(attrs) do
    Attached.Originals.Original.changeset(attrs) |> Repo.insert!()
  end

  defp insert_variant(attrs) do
    Variant.changeset(attrs) |> Repo.insert!()
  end

  defp storage_root do
    :attached |> Application.get_env(:disk, []) |> Keyword.get(:root)
  end

  # Mirror the worker's transforms-from-schema resolution to compute the
  # digest the worker will store under.
  defp expected_digest(variant) do
    transforms =
      struct(Attached.Test.User)
      |> Attached.Variants.transforms_for(:avatar, variant)
      |> Keyword.put(:variant_name, variant)

    Attached.Variants.transform_digest(transforms)
  end

  describe "perform/1" do
    @tag skip: not @image_tool_available
    test "generates and stores a variant for an image original" do
      fixture = Path.expand("../../support/fixtures/header.png", __DIR__)
      key = "transform_img_#{System.unique_integer([:positive])}"
      :ok = Attached.StorageBackends.Disk.upload(key, fixture)

      original =
        insert_original(%{
          key: key,
          filename: "header.png",
          content_type: "image/png",
          byte_size: File.stat!(fixture).size,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "avatar_attached_original_id"
        })

      assert :ok =
               perform_job(Attached.Variants.VariantTransformWorker, %{
                 "original_id" => original.id,
                 "record_module" => "Attached.Test.User",
                 "field" => "avatar",
                 "variant" => "thumb"
               })

      variant = Repo.get_by!(Variant, original_id: original.id, transform_digest: expected_digest(:thumb))
      assert Attached.StorageBackends.Disk.exists?(Variants.path_for(original, variant))
    end

    @tag skip: not (@ffmpeg_available and @image_tool_available)
    test "generates a variant for a video original via image previewer + transformer" do
      video_path = generate_test_video()
      on_exit(fn -> File.rm(video_path) end)

      key = "transform_vid_#{System.unique_integer([:positive])}"
      :ok = Attached.StorageBackends.Disk.upload(key, video_path)

      original =
        insert_original(%{
          key: key,
          filename: "test.mp4",
          content_type: "video/mp4",
          byte_size: File.stat!(video_path).size,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "avatar_attached_original_id"
        })

      assert :ok =
               perform_job(Attached.Variants.VariantTransformWorker, %{
                 "original_id" => original.id,
                 "record_module" => "Attached.Test.User",
                 "field" => "avatar",
                 "variant" => "thumb"
               })

      variant = Repo.get_by!(Variant, original_id: original.id, transform_digest: expected_digest(:thumb))
      assert Attached.StorageBackends.Disk.exists?(Variants.path_for(original, variant))
    end

    test "is idempotent when variant already exists" do
      key = "transform_idem_#{System.unique_integer([:positive])}"
      File.write!(Path.join([storage_root(), key]), "x")

      original =
        insert_original(%{
          key: key,
          filename: "x.txt",
          content_type: "text/plain",
          byte_size: 1,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "avatar_attached_original_id"
        })

      digest = expected_digest(:thumb)

      insert_variant(%{
        original_id: original.id,
        name: "thumb",
        transform_digest: digest,
        content_type: "image/png",
        byte_size: 1,
        checksum: "test=="
      })

      before_count = Repo.aggregate(Variant, :count)

      assert :ok =
               perform_job(Attached.Variants.VariantTransformWorker, %{
                 "original_id" => original.id,
                 "record_module" => "Attached.Test.User",
                 "field" => "avatar",
                 "variant" => "thumb"
               })

      assert Repo.aggregate(Variant, :count) == before_count
    end
  end

  defp generate_test_video do
    path = Path.join(System.tmp_dir!(), "transform_vid_#{System.unique_integer([:positive])}.mp4")

    System.cmd("ffmpeg", ~w(-f lavfi -i color=c=blue:size=64x64:rate=1 -t 1 -y) ++ [path], stderr_to_stdout: true)

    path
  end
end
