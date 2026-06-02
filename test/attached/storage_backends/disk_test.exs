defmodule Attached.StorageBackends.DiskTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Attached.TestRepo

  alias Attached.TestRepo, as: Repo
  alias Attached.Test.User

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    tmp_path = Path.join(System.tmp_dir!(), "disk_test_#{System.unique_integer([:positive])}.txt")
    File.write!(tmp_path, "hello world")
    on_exit(fn -> File.rm(tmp_path) end)

    {:ok, upload: %{path: tmp_path, filename: "test.txt", content_type: "text/plain"}}
  end

  defp write_tmp(content) do
    path = Path.join(System.tmp_dir!(), "disk_tmp_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  describe "path_for/1 security" do
    test "raises on blank key" do
      assert_raise ArgumentError, ~r/blank/, fn ->
        Attached.StorageBackends.Disk.path_for("")
      end
    end

    test "raises on nil key" do
      assert_raise ArgumentError, ~r/blank/, fn ->
        Attached.StorageBackends.Disk.path_for(nil)
      end
    end

    test "raises on dot-dot traversal" do
      assert_raise ArgumentError, ~r/traversal/, fn ->
        Attached.StorageBackends.Disk.path_for("../../etc/passwd")
      end
    end

    test "raises on single-dot segment" do
      assert_raise ArgumentError, ~r/traversal/, fn ->
        Attached.StorageBackends.Disk.path_for("./sneaky")
      end
    end

    test "raises on null byte" do
      assert_raise ArgumentError, ~r/null byte/, fn ->
        Attached.StorageBackends.Disk.path_for("evil\0key")
      end
    end

    test "accepts a normal key" do
      path = Attached.StorageBackends.Disk.path_for("abcdef1234")
      assert path =~ "/ab/cd/abcdef1234"
    end
  end

  describe "path_for/1 sharding" do
    test "first two chars become first shard, next two become second" do
      key = "abcdef1234"
      assert Attached.StorageBackends.Disk.path_for(key) =~ "/ab/cd/#{key}"
    end

    test "matches Active Storage two-level layout" do
      key = "xtapjjcjiudrlk3tmwyjgpuobabd"
      assert Attached.StorageBackends.Disk.path_for(key) =~ "/xt/ap/#{key}"
    end

    test "variant keys are sharded on their prefix" do
      key = "variants/someuuid/digest"
      assert Attached.StorageBackends.Disk.path_for(key) =~ "/va/ri/#{key}"
    end

    test "_variants/ namespace shards on the parent key and doesn't repeat the prefix" do
      key = "_variants/abcdef1234-thumb-aaaa"
      path = Attached.StorageBackends.Disk.path_for(key)

      assert path =~ "/_variants/ab/cd/abcdef1234-thumb-aaaa"
      refute path =~ "/_v/ar/"
      refute path =~ "_variants/ab/cd/_variants/"
    end

    test "uploaded file lands under sharded path", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      expected_path = Attached.StorageBackends.Disk.path_for(original.key)

      assert File.exists?(expected_path)
      assert expected_path =~ "/#{String.slice(original.key, 0, 2)}/#{String.slice(original.key, 2, 2)}/"
    end
  end

  describe "download_chunk/2" do
    test "returns the requested byte range", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      # "hello world" — bytes 0..4 = "hello"
      assert {:ok, "hello"} = Attached.StorageBackends.Disk.download_chunk(original.key, 0..4)
    end

    test "returns a middle range", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      # "hello world" — bytes 6..10 = "world"
      assert {:ok, "world"} = Attached.StorageBackends.Disk.download_chunk(original.key, 6..10)
    end

    test "returns error for a missing key" do
      assert {:error, :not_found} = Attached.StorageBackends.Disk.download_chunk("nonexistent", 0..4)
    end
  end

  describe "compose/2" do
    test "concatenates source files into destination" do
      key1 = "compose_a_#{System.unique_integer([:positive])}"
      key2 = "compose_b_#{System.unique_integer([:positive])}"
      dest = "compose_dest_#{System.unique_integer([:positive])}"

      :ok = Attached.StorageBackends.Disk.upload(key1, write_tmp("hello "))
      :ok = Attached.StorageBackends.Disk.upload(key2, write_tmp("world"))
      :ok = Attached.StorageBackends.Disk.compose([key1, key2], dest)

      assert {:ok, "hello world"} = Attached.StorageBackends.Disk.download(dest)
    after
      # cleanup is best-effort; unique integers ensure no collision between runs
      :ok
    end
  end
end
