defmodule Attached.Processors.ImagePreviewers.Epub.GnomeEpubThumbnailerTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.ImagePreviewers.Epub.GnomeEpubThumbnailer
  alias Attached.Test.ImagePreviewerFixtures

  @gnome_epub_thumbnailer_available not is_nil(System.find_executable("gnome-epub-thumbnailer"))

  setup do
    output =
      Path.join(
        System.tmp_dir!(),
        "gnome_epub_thumbnailer_test_#{System.unique_integer([:positive])}.png"
      )

    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  test "accept? returns true for application/epub+zip and false otherwise" do
    assert GnomeEpubThumbnailer.accept?("application/epub+zip")
    refute GnomeEpubThumbnailer.accept?("application/pdf")
  end

  @tag skip: not @gnome_epub_thumbnailer_available
  test "preview generates output image", %{output: output} do
    input = ImagePreviewerFixtures.minimal_epub_path()
    on_exit(fn -> File.rm(input) end)
    assert :ok = GnomeEpubThumbnailer.preview(input, output)
    assert File.exists?(output)
  end
end
