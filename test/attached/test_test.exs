defmodule Attached.TestTest do
  use Attached.DataCase, async: false

  alias Attached.Test.User
  alias Attached.Originals.Original

  setup do
    path =
      Path.join(System.tmp_dir!(), "attached_test_helper_#{System.unique_integer([:positive])}.txt")

    File.write!(path, "fixture body")
    on_exit(fn -> File.rm(path) end)

    {:ok, path: path}
  end

  describe "attach!/3 with attached" do
    test "attaches a file path and returns the updated record", %{path: path} do
      user = Repo.insert!(User.changeset(%User{}, %{name: "Test"}))

      updated = Attached.Test.attach!(user, :avatar, path)

      assert updated.avatar_attached_original_id != nil

      original = Repo.get!(Original, updated.avatar_attached_original_id)
      assert original.filename == Path.basename(path)
      assert original.content_type == "text/plain"
      assert original.byte_size == byte_size("fixture body")
    end

    test "infers content type from extension", %{path: path} do
      png_path = String.replace_suffix(path, ".txt", ".png")
      File.cp!(path, png_path)
      on_exit(fn -> File.rm(png_path) end)

      user = Repo.insert!(User.changeset(%User{}, %{name: "Test"}))
      updated = Attached.Test.attach!(user, :avatar, png_path)

      original = Repo.get!(Original, updated.avatar_attached_original_id)
      assert original.content_type == "image/png"
    end

    test "accepts an upload-shaped map", %{path: path} do
      user = Repo.insert!(User.changeset(%User{}, %{name: "Test"}))

      upload = %{path: path, filename: "explicit.txt", content_type: "text/x-custom"}
      updated = Attached.Test.attach!(user, :avatar, upload)

      original = Repo.get!(Original, updated.avatar_attached_original_id)
      assert original.filename == "explicit.txt"
      assert original.content_type == "text/x-custom"
    end

    test "accepts an existing original (re-attach without storage I/O)", %{path: path} do
      user1 = Repo.insert!(User.changeset(%User{}, %{name: "User 1"}))
      user1 = Attached.Test.attach!(user1, :avatar, path)
      original = Repo.get!(Original, user1.avatar_attached_original_id)

      user2 = Repo.insert!(User.changeset(%User{}, %{name: "User 2"}))
      updated = Attached.Test.attach!(user2, :avatar, original)

      assert updated.avatar_attached_original_id == original.id
    end
  end

  describe "attach!/3 errors" do
    test "raises for unknown field", %{path: path} do
      user = Repo.insert!(User.changeset(%User{}, %{name: "Test"}))

      assert_raise ArgumentError, ~r/does not have an attached field :nope/, fn ->
        Attached.Test.attach!(user, :nope, path)
      end
    end
  end
end
