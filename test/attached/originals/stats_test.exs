defmodule Attached.Originals.StatsTest do
  use Attached.DataCase

  alias Attached.Originals
  alias Attached.Originals.Stats

  @opts [owner_table: "users", owner_field: "avatar_attached_original_id"]

  describe "overview/0" do
    test "returns zeros when there are no originals" do
      assert Stats.overview() == %{record_count: 0, total_bytes: 0}
    end

    test "aggregates record count and total bytes" do
      Originals.create_from_stream!(["aaaaa"], @opts ++ [filename: "a.txt"])
      Originals.create_from_stream!(["bbbbbbbbbb"], @opts ++ [filename: "b.txt"])

      assert Stats.overview() == %{record_count: 2, total_bytes: 15}
    end
  end

  describe "by_content_type/0" do
    test "returns an empty list when there are no originals" do
      assert Stats.by_content_type() == []
    end

    test "groups by major MIME type and sorts by count descending" do
      # two text/plain + one image/png → image and text groups
      Originals.create_from_stream!(["aaaaa"], @opts ++ [filename: "a.txt", content_type: "text/plain"])
      Originals.create_from_stream!(["bbbbb"], @opts ++ [filename: "b.txt", content_type: "text/plain"])

      Originals.create_from_stream!(
        [<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>],
        @opts ++ [filename: "c.png", content_type: "image/png"]
      )

      assert Stats.by_content_type() == [
               %{type: "text", record_count: 2},
               %{type: "image", record_count: 1}
             ]
    end
  end

  describe "by_owner_group/0" do
    test "returns an empty list when there are no originals" do
      assert Stats.by_owner_group() == []
    end

    test "aggregates per owner (table, field) and sorts by count desc" do
      Originals.create_from_stream!(["aa"], @opts ++ [filename: "a.txt"])
      Originals.create_from_stream!(["bbbb"], @opts ++ [filename: "b.txt"])

      Originals.create_from_stream!(["c"],
        filename: "c.txt",
        owner_table: "posts",
        owner_field: "cover_attached_original_id"
      )

      assert [
               %{
                 owner_table: "users",
                 owner_field: "avatar_attached_original_id",
                 original_count: 2,
                 total_bytes: 6
               },
               %{
                 owner_table: "posts",
                 owner_field: "cover_attached_original_id",
                 original_count: 1,
                 total_bytes: 1
               }
             ] = Stats.by_owner_group()
    end
  end

  describe "by_storage_backend/0" do
    test "returns an empty list when there are no originals" do
      assert Stats.by_storage_backend() == []
    end

    test "groups by storage backend with size aggregates" do
      Originals.create_from_stream!(["aaaaa"], @opts ++ [filename: "a.txt"])
      Originals.create_from_stream!(["bbbbbbbbbb"], @opts ++ [filename: "b.txt"])

      assert [%{storage_backend: backend, record_count: 2, total_bytes: 15, avg_bytes: avg, max_bytes: 10}] =
               Stats.by_storage_backend()

      assert is_binary(backend)
      # avg/1 returns Decimal on Postgres, float on SQLite — just check it's numeric
      assert avg != nil
    end
  end
end
