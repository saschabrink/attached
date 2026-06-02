defmodule Attached.Variants.VariantTest do
  use Attached.DataCase

  alias Attached.Variants.Variant

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset = Variant.changeset(valid_attrs())
      assert changeset.valid?
    end

    test "metadata defaults to empty map" do
      attrs = valid_attrs()
      variant = Variant.changeset(attrs) |> Ecto.Changeset.apply_changes()
      assert variant.metadata == %{}
    end

    test "metadata can be supplied" do
      attrs = valid_attrs() |> Map.put(:metadata, %{"width" => 100})
      variant = Variant.changeset(attrs) |> Ecto.Changeset.apply_changes()
      assert variant.metadata == %{"width" => 100}
    end

    test "requires original_id, name, transform_digest, content_type, byte_size, checksum" do
      changeset = Variant.changeset(%{})
      refute changeset.valid?

      for field <- [:original_id, :name, :transform_digest, :content_type, :byte_size, :checksum] do
        assert {"can't be blank", _} = changeset.errors[field]
      end
    end

    test "name must match [a-z0-9_]+ — hyphens rejected" do
      changeset = Variant.changeset(valid_attrs() |> Map.put(:name, "header-image"))
      refute changeset.valid?
      assert {_msg, [validation: :format]} = changeset.errors[:name]
    end

    test "name accepts underscores" do
      changeset = Variant.changeset(valid_attrs() |> Map.put(:name, "header_image"))
      assert changeset.valid?
    end

    test "name accepts digits" do
      changeset = Variant.changeset(valid_attrs() |> Map.put(:name, "thumb_2x"))
      assert changeset.valid?
    end
  end

  describe "DB constraints" do
    test "unique on (original_id, transform_digest)" do
      original = insert_original!()

      attrs = %{
        original_id: original.id,
        name: "thumb",
        transform_digest: "abcd1234",
        content_type: "image/png",
        byte_size: 100,
        checksum: "test=="
      }

      assert {:ok, _} = attrs |> Variant.changeset() |> Repo.insert()

      assert {:error, changeset} =
               attrs
               |> Map.put(:name, "renamed")
               |> Variant.changeset()
               |> Repo.insert()

      assert {_, [constraint: :unique, constraint_name: _]} =
               changeset.errors[:original_id] || changeset.errors[{:original_id, :transform_digest}]
    end

    test "same transform_digest allowed for different originals" do
      original_a = insert_original!()
      original_b = insert_original!()

      attrs = fn original_id ->
        %{
          original_id: original_id,
          name: "thumb",
          transform_digest: "shared_digest",
          content_type: "image/png",
          byte_size: 100,
          checksum: "test=="
        }
      end

      assert {:ok, _} = attrs.(original_a.id) |> Variant.changeset() |> Repo.insert()
      assert {:ok, _} = attrs.(original_b.id) |> Variant.changeset() |> Repo.insert()
    end

    test "cascade-deletes when parent original is removed" do
      original = insert_original!()

      {:ok, _variant} =
        %{
          original_id: original.id,
          name: "thumb",
          transform_digest: "abcd1234",
          content_type: "image/png",
          byte_size: 100,
          checksum: "test=="
        }
        |> Variant.changeset()
        |> Repo.insert()

      Repo.delete!(original)

      assert Repo.aggregate(Variant, :count) == 0
    end

    # FK enforcement on insert is covered indirectly by the cascade-delete
    # test above (which depends on the FK being live). Skipping a direct
    # rejection test — Ecto's foreign_key_constraint/2 name matching against
    # the SQLite adapter's emitted constraint name isn't reliable here.
  end

  defp valid_attrs do
    %{
      original_id: Ecto.UUID.generate(),
      name: "thumb",
      transform_digest: "abcd1234",
      content_type: "image/png",
      byte_size: 1024,
      checksum: "test=="
    }
  end

  defp insert_original!(overrides \\ %{}) do
    base = %{
      key: "test_original_#{System.unique_integer([:positive])}",
      filename: "test.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum: "abc",
      storage_backend: "Attached.StorageBackends.Disk",
      owner_table: "users",
      owner_field: "avatar_attached_original_id"
    }

    base
    |> Map.merge(overrides)
    |> Attached.Originals.Original.changeset()
    |> Repo.insert!()
  end
end
