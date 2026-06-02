defmodule Attached.Processors.Transformers.Document.PandocTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.Transformers.Document.Pandoc
  alias Attached.Test.ImagePreviewerFixtures

  @available not is_nil(System.find_executable("pandoc"))

  setup do
    output =
      Path.join(System.tmp_dir!(), "pandoc_test_#{System.unique_integer([:positive])}.md")

    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  describe "accept?/2" do
    test "accepts known doc input types when target is text/markdown" do
      assert Pandoc.accept?("application/epub+zip", "text/markdown")
      assert Pandoc.accept?("text/html", "text/markdown")

      assert Pandoc.accept?(
               "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
               "text/markdown"
             )
    end

    test "rejects unknown input types" do
      refute Pandoc.accept?("image/png", "text/markdown")
      refute Pandoc.accept?("video/mp4", "text/markdown")
    end

    test "rejects targets other than text/markdown" do
      refute Pandoc.accept?("application/epub+zip", "text/plain")
      refute Pandoc.accept?("application/epub+zip", "text/html")
    end
  end

  describe "transform/3" do
    @tag skip: not @available
    test "converts an EPUB to markdown", %{output: output} do
      input = ImagePreviewerFixtures.minimal_epub_path()
      on_exit(fn -> File.rm(input) end)

      assert :ok = Pandoc.transform(input, [], output)
      assert File.exists?(output)
      # The minimal EPUB has only a cover image and an empty nav, so
      # pandoc emits a reference to the cover. We just need to confirm
      # that the conversion ran and produced non-empty output.
      assert File.read!(output) =~ "cover.png"
    end

    @tag skip: not @available
    test "converts an HTML file to markdown", %{output: output} do
      input = Path.join(System.tmp_dir!(), "pandoc_test_#{System.unique_integer([:positive])}.html")
      File.write!(input, "<h1>Heading</h1><p>A <strong>bold</strong> paragraph.</p>")
      on_exit(fn -> File.rm(input) end)

      assert :ok = Pandoc.transform(input, [], output)
      assert File.read!(output) =~ "# Heading"
    end

    @tag skip: @available
    test "returns an error tuple when pandoc is missing", %{output: output} do
      assert {:error, _} = Pandoc.transform("/nonexistent.epub", [], output)
    end
  end
end
