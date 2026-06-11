defmodule Attached.VariantsTest.RivalTransform do
  # Simulates losing the process/3 race deterministically: by the time this
  # "transform" finishes, a concurrent caller has already inserted the variant
  # row for the same (original_id, transform_digest).
  def transform(_input_path, transforms, output_path) do
    %{
      original_id: Keyword.fetch!(transforms, :original_id),
      name: "race",
      transform_digest: Attached.Variants.transform_digest(transforms),
      content_type: "image/png",
      byte_size: 1,
      checksum: "rival"
    }
    |> Attached.Variants.Variant.changeset()
    |> Attached.TestRepo.insert!()

    File.write!(output_path, "x")
    :ok
  end
end

defmodule Attached.VariantsTest do
  use Attached.DataCase, async: false

  defp insert_original(attrs) do
    Attached.Originals.Original.changeset(attrs) |> Repo.insert!()
  end

  defp upload_dummy(key) do
    tmp = Path.join(System.tmp_dir!(), "variants_test_#{key}")
    File.write!(tmp, "dummy")
    :ok = Attached.StorageBackends.upload(key, tmp)
    File.rm(tmp)
    :ok
  end

  describe "process/3 concurrency" do
    test "returns the existing row when a concurrent caller inserts first" do
      key = "race_#{System.unique_integer([:positive])}"
      :ok = upload_dummy(key)

      original =
        insert_original(%{
          key: key,
          filename: "pic.png",
          content_type: "image/png",
          byte_size: 5,
          checksum: "abc",
          storage_backend: "local",
          owner_table: "users",
          owner_field: "pic_attached_original_id"
        })

      transforms = [
        fn: &Attached.VariantsTest.RivalTransform.transform/3,
        mime_type: "image/png",
        variant_name: :race,
        original_id: original.id
      ]

      digest = Attached.Variants.transform_digest(transforms)
      variant = Attached.Variants.process(original, digest, transforms)

      assert variant.checksum == "rival"
      assert Attached.Variants.count() == 1
    end
  end

  describe "process/3 dispatch error branches" do
    test "non-image original with non-image target and no matching transformer raises" do
      key = "no_transformer_#{System.unique_integer([:positive])}"
      :ok = upload_dummy(key)

      original =
        insert_original(%{
          key: key,
          filename: "song.mp3",
          content_type: "audio/mpeg",
          byte_size: 5,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "song_attached_original_id"
        })

      transforms = [mime_type: "audio/ogg", variant_name: :ogg]
      digest = Attached.Variants.transform_digest(transforms)

      assert_raise Attached.Variants.NoTransformerError,
                   ~r/audio\/mpeg → audio\/ogg/,
                   fn -> Attached.Variants.process(original, digest, transforms) end
    end

    test "non-image original with image target and no image previewer raises" do
      key = "no_image_previewer_#{System.unique_integer([:positive])}"
      :ok = upload_dummy(key)

      original =
        insert_original(%{
          key: key,
          filename: "song.mp3",
          content_type: "audio/mpeg",
          byte_size: 5,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "song_attached_original_id"
        })

      transforms = [mime_type: "image/png", variant_name: :preview]
      digest = Attached.Variants.transform_digest(transforms)

      assert_raise Attached.Variants.NoTransformerError,
                   ~r/audio\/mpeg → image\/png/,
                   fn -> Attached.Variants.process(original, digest, transforms) end
    end

    test "image target with an image previewer but no image transformer raises" do
      key = "no_image_transformer_#{System.unique_integer([:positive])}"
      :ok = upload_dummy(key)

      original =
        insert_original(%{
          key: key,
          filename: "doc.pdf",
          content_type: "application/pdf",
          byte_size: 5,
          checksum: "abc",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "doc_attached_original_id"
        })

      # Swap the transformers registry to an empty list so the image-transformer
      # stage of the image previewer fallback can't match.
      original_config = Application.get_env(:attached, :transformers)
      Application.put_env(:attached, :transformers, [])

      on_exit(fn ->
        case original_config do
          nil -> Application.delete_env(:attached, :transformers)
          value -> Application.put_env(:attached, :transformers, value)
        end
      end)

      transforms = [mime_type: "image/png", variant_name: :preview]
      digest = Attached.Variants.transform_digest(transforms)

      assert_raise Attached.Variants.NoTransformerError,
                   ~r/application\/pdf → image\/png/,
                   fn -> Attached.Variants.process(original, digest, transforms) end
    end
  end

  describe "previewable?/1" do
    test "true for image originals" do
      original = %Attached.Originals.Original{content_type: "image/png"}
      assert Attached.Variants.previewable?(original)
    end

    test "true for types with a registered image previewer" do
      original = %Attached.Originals.Original{content_type: "application/pdf"}
      # Depends on pdftoppm/mutool availability — skip when unavailable.
      if Attached.Processors.ImagePreviewers.find_for("application/pdf") do
        assert Attached.Variants.previewable?(original)
      end
    end

    test "false for types with no image previewer" do
      original = %Attached.Originals.Original{content_type: "audio/mpeg"}
      refute Attached.Variants.previewable?(original)
    end

    test "false for nil content type" do
      refute Attached.Variants.previewable?(%Attached.Originals.Original{content_type: nil})
    end
  end

  describe "preview_url/1" do
    test "returns :not_previewable for types without an image previewer" do
      original = %Attached.Originals.Original{
        id: Ecto.UUID.generate(),
        key: "unused",
        content_type: "audio/mpeg",
        filename: "song.mp3"
      }

      assert {:error, :not_previewable} = Attached.Variants.preview_url(original)
    end
  end
end
