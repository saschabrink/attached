defmodule Attached.Originals.OriginalTest do
  use Attached.DataCase, async: false
  use Oban.Testing, repo: Attached.TestRepo

  alias Attached.Test.User

  setup do
    tmp_path = Path.join(System.tmp_dir!(), "original_test_#{System.unique_integer([:positive])}.txt")
    File.write!(tmp_path, "hello world")
    on_exit(fn -> File.rm(tmp_path) end)

    {:ok, upload: %{path: tmp_path, filename: "test.txt", content_type: "text/plain"}}
  end

  describe "image?/1" do
    test "returns true for image/* content types" do
      assert Attached.Originals.Original.image?(%Attached.Originals.Original{content_type: "image/png"})
      assert Attached.Originals.Original.image?(%Attached.Originals.Original{content_type: "image/jpeg"})
      assert Attached.Originals.Original.image?(%Attached.Originals.Original{content_type: "image/webp"})
    end

    test "returns false for non-image content types" do
      refute Attached.Originals.Original.image?(%Attached.Originals.Original{content_type: "text/plain"})
      refute Attached.Originals.Original.image?(%Attached.Originals.Original{content_type: "video/mp4"})
      refute Attached.Originals.Original.image?(%Attached.Originals.Original{content_type: "application/pdf"})
    end
  end

  describe "video?/1" do
    test "returns true for video/* content types" do
      assert Attached.Originals.Original.video?(%Attached.Originals.Original{content_type: "video/mp4"})
    end

    test "returns false for non-video content types" do
      refute Attached.Originals.Original.video?(%Attached.Originals.Original{content_type: "image/png"})
    end
  end

  describe "audio?/1" do
    test "returns true for audio/* content types" do
      assert Attached.Originals.Original.audio?(%Attached.Originals.Original{content_type: "audio/mpeg"})
    end

    test "returns false for non-audio content types" do
      refute Attached.Originals.Original.audio?(%Attached.Originals.Original{content_type: "image/png"})
    end
  end

  describe "changeset/1" do
    test "is invalid when required fields are missing" do
      changeset = Attached.Originals.Original.changeset(%{})
      refute changeset.valid?

      errors = Keyword.keys(changeset.errors)
      assert :key in errors
      assert :filename in errors
      assert :content_type in errors
      assert :byte_size in errors
      assert :checksum in errors
    end

    test "is valid with all required fields" do
      changeset =
        Attached.Originals.Original.changeset(%{
          key: "abc123",
          filename: "file.txt",
          content_type: "text/plain",
          byte_size: 11,
          checksum: "abc==",
          storage_backend: "Attached.StorageBackends.Disk",
          owner_table: "users",
          owner_field: "avatar"
        })

      assert changeset.valid?
    end
  end

  describe "key format" do
    test "key is 28-character base36", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()

      original = Repo.get!(Attached.Originals.Original, user.avatar_attached_original_id)
      assert String.length(original.key) == 28
      assert original.key =~ ~r/\A[0-9a-z]{28}\z/
    end
  end
end
