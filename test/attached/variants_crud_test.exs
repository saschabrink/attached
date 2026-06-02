defmodule Attached.VariantsCrudTest do
  @moduledoc """
  CRUD-layer tests for `Attached.Variants` against the new
  `attached_variants` table. The legacy generation pipeline is exercised
  separately in `Attached.VariantsTest`.
  """

  use Attached.DataCase

  alias Attached.Variants
  alias Attached.Variants.Variant

  describe "list/1" do
    test "returns [] when empty" do
      assert Variants.list() == []
    end

    test "returns inserted variants" do
      original = insert_original!()
      insert_variant!(original, "thumb", "aaaa")
      insert_variant!(original, "medium", "bbbb")

      variants = Variants.list()
      assert length(variants) == 2
      assert Enum.all?(variants, &match?(%Variant{}, &1))
    end

    test "supports :order_by, :limit, :offset" do
      original = insert_original!()
      insert_variant!(original, "a", "1111")
      insert_variant!(original, "b", "2222")
      insert_variant!(original, "c", "3333")

      result = Variants.list(order_by: [asc: :name], limit: 2)
      assert Enum.map(result, & &1.name) == ["a", "b"]

      result = Variants.list(order_by: [asc: :name], limit: 2, offset: 1)
      assert Enum.map(result, & &1.name) == ["b", "c"]
    end

    test "supports :preload" do
      original = insert_original!()
      insert_variant!(original, "thumb", "aaaa")

      [variant] = Variants.list(preload: :original)
      assert variant.original.id == original.id
    end

    test "supports :query escape hatch" do
      original = insert_original!()
      insert_variant!(original, "thumb", "aaaa")
      insert_variant!(original, "medium", "bbbb")

      result = Variants.list(query: &where(&1, [v], v.name == "thumb"))
      assert [%{name: "thumb"}] = result
    end
  end

  describe "get/2 and get!/2" do
    test "get/2 returns nil for unknown id" do
      assert Variants.get(Ecto.UUID.generate()) == nil
    end

    test "get!/2 raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Variants.get!(Ecto.UUID.generate()) end
    end

    test "returns the variant" do
      original = insert_original!()
      variant = insert_variant!(original, "thumb", "aaaa")

      assert %Variant{id: id} = Variants.get(variant.id)
      assert id == variant.id

      assert %Variant{id: ^id} = Variants.get!(variant.id)
    end
  end

  describe "count/1" do
    test "returns 0 when empty" do
      assert Variants.count() == 0
    end

    test "counts inserted variants" do
      original = insert_original!()
      insert_variant!(original, "thumb", "aaaa")
      insert_variant!(original, "medium", "bbbb")

      assert Variants.count() == 2
    end
  end

  describe "paginate/1" do
    test "returns entries + metadata" do
      original = insert_original!()

      for i <- 1..5 do
        insert_variant!(original, "v#{i}", String.duplicate("#{i}", 4))
      end

      result = Variants.paginate(order_by: [asc: :name], per_page: 2, page: 1)
      assert result.total == 5
      assert result.per_page == 2
      assert result.page == 1
      assert length(result.entries) == 2

      result_p2 = Variants.paginate(order_by: [asc: :name], per_page: 2, page: 2)
      assert length(result_p2.entries) == 2
      refute Enum.any?(result.entries, &(&1.id in Enum.map(result_p2.entries, fn v -> v.id end)))
    end
  end

  describe "path_for/3" do
    test "stores variants under the _variants/ namespace" do
      original = %Attached.Originals.Original{key: "abcdef1234"}
      path = Variants.path_for(original, "thumb", "aaaa-rest-of-digest")

      assert path == "_variants/abcdef1234-thumb-aaaa"
    end
  end

  describe "get_by_path/1" do
    test "resolves a namespaced variant path back to the variant" do
      original = insert_original!()
      variant = insert_variant!(original, "thumb", "aaaa")

      path = Variants.path_for(original, variant)
      assert Variants.get_by_path(path).id == variant.id
    end

    test "returns nil for paths that don't refer to a variant" do
      assert Variants.get_by_path("_variants/unknown-thumb-aaaa") == nil
      assert Variants.get_by_path("not-a-variant-path") == nil
    end
  end

  defp insert_original! do
    %{
      key: "test_original_#{System.unique_integer([:positive])}",
      filename: "test.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum: "abc",
      storage_backend: "Attached.StorageBackends.Disk",
      owner_table: "users",
      owner_field: "avatar_attached_original_id"
    }
    |> Attached.Originals.Original.changeset()
    |> Repo.insert!()
  end

  defp insert_variant!(original, name, transform_digest) do
    %{
      original_id: original.id,
      name: name,
      transform_digest: transform_digest,
      content_type: "image/png",
      byte_size: 100,
      checksum: "test=="
    }
    |> Variant.changeset()
    |> Repo.insert!()
  end
end
