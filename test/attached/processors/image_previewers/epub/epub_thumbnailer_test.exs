defmodule Attached.Processors.ImagePreviewers.Epub.EpubThumbnailerTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.ImagePreviewers.Epub.EpubThumbnailer
  alias Attached.Test.ImagePreviewerFixtures

  @epub_thumbnailer_available not is_nil(System.find_executable("epub-thumbnailer"))

  setup do
    output =
      Path.join(System.tmp_dir!(), "epub_thumbnailer_test_#{System.unique_integer([:positive])}.png")

    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  test "accept? returns true for application/epub+zip and false otherwise" do
    assert EpubThumbnailer.accept?("application/epub+zip")
    refute EpubThumbnailer.accept?("application/pdf")
  end

  @tag skip: not @epub_thumbnailer_available
  test "preview generates output image", %{output: output} do
    input = ImagePreviewerFixtures.minimal_epub_path()
    on_exit(fn -> File.rm(input) end)
    assert :ok = EpubThumbnailer.preview(input, output)
    assert File.exists?(output)
  end
end
