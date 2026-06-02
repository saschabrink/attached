defmodule Attached.Ecto.CRUDTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Attached.Originals.Original
  alias Attached.Ecto.CRUD
  alias Attached.TestRepo, as: Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  describe "list/2" do
    test "returns all rows by default" do
      insert_original!(filename: "a.txt")
      insert_original!(filename: "b.txt")

      assert length(CRUD.list(Original)) == 2
    end

    test "applies :query for ad-hoc composition" do
      insert_original!(filename: "keep.txt")
      insert_original!(filename: "drop.txt")

      filter = &where(&1, [b], b.filename == "keep.txt")

      assert [%Original{filename: "keep.txt"}] = CRUD.list(Original, query: filter)
    end

    test "applies :order_by, :limit and :offset" do
      insert_original!(filename: "a.txt")
      insert_original!(filename: "b.txt")
      insert_original!(filename: "c.txt")

      assert [%{filename: "b.txt"}] =
               CRUD.list(Original, order_by: [asc: :filename], limit: 1, offset: 1)
    end

    test ":select projects to the given fields only" do
      insert_original!(filename: "only.txt", content_type: "text/plain")

      assert [%Original{filename: "only.txt", content_type: nil}] =
               CRUD.list(Original, select: [:filename])
    end

    test ":distinct with an atom returns scalar distinct values" do
      insert_original!(content_type: "text/plain")
      insert_original!(content_type: "text/plain")
      insert_original!(content_type: "image/png")

      assert ["image/png", "text/plain"] =
               CRUD.list(Original, distinct: :content_type)
    end

    test ":distinct with a list returns distinct tuples as maps" do
      insert_original!(owner_table: "users", owner_field: "avatar")
      insert_original!(owner_table: "users", owner_field: "avatar")
      insert_original!(owner_table: "posts", owner_field: "cover")

      assert [
               %{owner_table: "posts", owner_field: "cover"},
               %{owner_table: "users", owner_field: "avatar"}
             ] = CRUD.list(Original, distinct: [:owner_table, :owner_field])
    end

    test "raises on unsupported option" do
      assert_raise ArgumentError, ~r/:bogus/, fn ->
        CRUD.list(Original, bogus: true)
      end
    end
  end

  describe "get/3 and get!/3" do
    test "get/3 returns the row" do
      original = insert_original!()
      assert %Original{id: id} = CRUD.get(Original, original.id)
      assert id == original.id
    end

    test "get/3 returns nil when not found" do
      assert CRUD.get(Original, Ecto.UUID.generate()) == nil
    end

    test "get!/3 raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        CRUD.get!(Original, Ecto.UUID.generate())
      end
    end

    test "get/3 applies :query before fetching" do
      original = insert_original!(filename: "match.txt")
      other = insert_original!(filename: "nope.txt")

      filter = &where(&1, [b], b.filename == "match.txt")

      assert %Original{} = CRUD.get(Original, original.id, query: filter)
      assert CRUD.get(Original, other.id, query: filter) == nil
    end
  end

  describe "get_by/3" do
    test "fetches by keyword clauses" do
      original = insert_original!(filename: "by-key.txt")
      assert %Original{id: id} = CRUD.get_by(Original, filename: "by-key.txt")
      assert id == original.id
    end

    test "returns nil when no match" do
      assert CRUD.get_by(Original, filename: "missing.txt") == nil
    end
  end

  describe "count/2" do
    test "counts all rows" do
      insert_original!()
      insert_original!()

      assert CRUD.count(Original) == 2
    end

    test "respects :query" do
      insert_original!(filename: "keep.txt")
      insert_original!(filename: "drop.txt")

      filter = &where(&1, [b], b.filename == "keep.txt")

      assert CRUD.count(Original, query: filter) == 1
    end
  end

  describe "paginate/2" do
    test "returns entries/total/page/per_page with defaults" do
      insert_original!()

      assert %{entries: [%Original{}], total: 1, page: 1, per_page: 25} =
               CRUD.paginate(Original)
    end

    test "slices pages by :page and :per_page" do
      for i <- 1..5, do: insert_original!(filename: "f-#{i}.txt")

      page1 = CRUD.paginate(Original, page: 1, per_page: 2, order_by: [asc: :filename])
      page2 = CRUD.paginate(Original, page: 2, per_page: 2, order_by: [asc: :filename])
      page3 = CRUD.paginate(Original, page: 3, per_page: 2, order_by: [asc: :filename])

      assert Enum.map(page1.entries, & &1.filename) == ["f-1.txt", "f-2.txt"]
      assert Enum.map(page2.entries, & &1.filename) == ["f-3.txt", "f-4.txt"]
      assert Enum.map(page3.entries, & &1.filename) == ["f-5.txt"]
      assert page1.total == 5
    end

    test "clamps page and per_page to 1 minimum" do
      insert_original!()

      assert %{page: 1, per_page: 1} = CRUD.paginate(Original, page: 0, per_page: 0)
    end

    test "total reflects :query filter" do
      insert_original!(filename: "keep.txt")
      insert_original!(filename: "drop.txt")

      filter = &where(&1, [b], b.filename == "keep.txt")

      assert %{total: 1, entries: [%Original{filename: "keep.txt"}]} =
               CRUD.paginate(Original, query: filter)
    end
  end

  defp insert_original!(attrs \\ []) do
    defaults = %{
      key: Original.generate_key(),
      filename: "file-#{System.unique_integer([:positive])}.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum: "abc",
      storage_backend: "Test",
      owner_table: "users",
      owner_field: "avatar_attached_original_id"
    }

    defaults
    |> Map.merge(Map.new(attrs))
    |> Original.changeset()
    |> Repo.insert!()
  end
end
