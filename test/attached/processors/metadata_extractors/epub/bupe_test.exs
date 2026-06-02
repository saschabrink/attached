defmodule Attached.Processors.MetadataExtractors.Epub.BupeTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.MetadataExtractors.Epub.Bupe
  alias Attached.Test.ImagePreviewerFixtures

  @available Code.ensure_loaded?(BUPE)

  describe "accept?/1" do
    test "true for application/epub+zip" do
      assert Bupe.accept?("application/epub+zip")
    end

    test "false for unrelated content types" do
      refute Bupe.accept?("application/pdf")
      refute Bupe.accept?("image/png")
    end
  end

  describe "metadata/1" do
    @tag skip: not @available
    test "extracts title, language and identifier from a minimal EPUB" do
      input = ImagePreviewerFixtures.minimal_epub_path()
      on_exit(fn -> File.rm(input) end)

      meta = Bupe.metadata(input)

      assert meta[:title] == "Test"
      assert meta[:language] == "en"
      assert meta[:identifier] == "test-book"
    end

    @tag skip: not @available
    test "returns an empty map for a non-EPUB file" do
      not_an_epub = Path.join(System.tmp_dir!(), "bupe_test_#{System.unique_integer([:positive])}.txt")
      File.write!(not_an_epub, "not an epub")
      on_exit(fn -> File.rm(not_an_epub) end)

      assert Bupe.metadata(not_an_epub) == %{}
    end
  end
end
