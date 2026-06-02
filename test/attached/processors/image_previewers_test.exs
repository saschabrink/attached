defmodule Attached.Processors.ImagePreviewersTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.ImagePreviewers

  @ffmpeg_available not is_nil(System.find_executable("ffmpeg"))
  @any_pdf_available not is_nil(System.find_executable("pdftoppm")) or
                       not is_nil(System.find_executable("mutool"))
  @any_epub_available not is_nil(System.find_executable("epub-thumbnailer")) or
                        not is_nil(System.find_executable("gnome-epub-thumbnailer"))

  describe "list/0" do
    test "defaults to all built-in previewers" do
      assert ImagePreviewers.list() == [
               ImagePreviewers.Video.FFmpeg,
               ImagePreviewers.Pdf.Pdftoppm,
               ImagePreviewers.Pdf.Mutool,
               ImagePreviewers.Epub.EpubThumbnailer,
               ImagePreviewers.Epub.GnomeEpubThumbnailer
             ]
    end
  end

  describe "find_for/1" do
    @tag skip: not @ffmpeg_available
    test "returns Video.FFmpeg for video/mp4" do
      assert ImagePreviewers.find_for("video/mp4") == ImagePreviewers.Video.FFmpeg
    end

    @tag skip: not @any_pdf_available
    test "returns a Pdf previewer for application/pdf" do
      assert ImagePreviewers.find_for("application/pdf") in [
               ImagePreviewers.Pdf.Pdftoppm,
               ImagePreviewers.Pdf.Mutool
             ]
    end

    @tag skip: not @any_epub_available
    test "returns an Epub previewer for application/epub+zip" do
      assert ImagePreviewers.find_for("application/epub+zip") in [
               ImagePreviewers.Epub.EpubThumbnailer,
               ImagePreviewers.Epub.GnomeEpubThumbnailer
             ]
    end

    test "returns nil for an unrecognized type" do
      assert ImagePreviewers.find_for("application/json") == nil
    end
  end
end
