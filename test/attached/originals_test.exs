defmodule Attached.OriginalsTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Attached.TestRepo

  alias Attached.TestRepo, as: Repo
  alias Attached.Originals

  @opts [owner_table: "users", owner_field: "avatar_attached_original_id"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  describe "create_from_upload!/2" do
    test "ingests a duck-typed upload map" do
      tmp = tmp_file("hello upload")

      original =
        Originals.create_from_upload!(
          %{path: tmp, filename: "greeting.txt", content_type: "text/plain"},
          @opts
        )

      assert original.filename == "greeting.txt"
      assert original.content_type == "text/plain"
      assert original.byte_size == byte_size("hello upload")
      assert Repo.get!(Attached.Originals.Original, original.id)
    end

    test "returns existing original unchanged" do
      existing = %Attached.Originals.Original{id: Ecto.UUID.generate()}
      assert Originals.create_from_upload!(existing, @opts) == existing
    end
  end

  describe "create_from_file!/2" do
    test "ingests from a local path" do
      tmp = tmp_file("hello file")

      original = Originals.create_from_file!(tmp, @opts)

      assert original.filename == Path.basename(tmp)
      assert original.byte_size == byte_size("hello file")
    end

    test "respects :filename and :content_type overrides" do
      tmp = tmp_file("hello override")

      original =
        Originals.create_from_file!(
          tmp,
          @opts ++ [filename: "custom.txt", content_type: "text/plain"]
        )

      assert original.filename == "custom.txt"
      assert original.content_type == "text/plain"
    end
  end

  describe "create_from_stream!/2" do
    test "ingests an Enumerable of binary chunks" do
      stream = ["chunk-1 ", "chunk-2 ", "chunk-3"]

      original = Originals.create_from_stream!(stream, @opts ++ [filename: "stream.txt"])

      assert original.filename == "stream.txt"
      assert original.byte_size == byte_size("chunk-1 chunk-2 chunk-3")
    end

    test "raises without :filename" do
      assert_raise ArgumentError, ~r/:filename/, fn ->
        Originals.create_from_stream!(["data"], @opts)
      end
    end
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "originals_test_#{System.unique_integer([:positive])}.txt")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
