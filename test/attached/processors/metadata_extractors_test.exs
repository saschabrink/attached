defmodule Attached.Processors.MetadataExtractorsTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.MetadataExtractors

  @ffprobe_available not is_nil(System.find_executable("ffprobe"))
  @image_available Code.ensure_loaded?(Vix.Vips.Image) or
                     not is_nil(System.find_executable("identify"))
  @bupe_available Code.ensure_loaded?(BUPE)

  describe "list/0" do
    test "defaults to all built-in extractors" do
      assert MetadataExtractors.list() == [
               MetadataExtractors.Image.Vix,
               MetadataExtractors.Image.ImageMagick,
               MetadataExtractors.Video.FFmpeg,
               MetadataExtractors.Audio.FFmpeg,
               MetadataExtractors.Epub.Bupe
             ]
    end
  end

  describe "find_for/1" do
    @tag skip: not @image_available
    test "returns an Image extractor for image/png" do
      mod = MetadataExtractors.find_for("image/png")

      assert mod in [
               MetadataExtractors.Image.Vix,
               MetadataExtractors.Image.ImageMagick
             ]
    end

    @tag skip: not @ffprobe_available
    test "returns Video.FFmpeg for video/mp4" do
      assert MetadataExtractors.find_for("video/mp4") == MetadataExtractors.Video.FFmpeg
    end

    @tag skip: not @ffprobe_available
    test "returns Audio.FFmpeg for audio/mpeg" do
      assert MetadataExtractors.find_for("audio/mpeg") == MetadataExtractors.Audio.FFmpeg
    end

    @tag skip: not @bupe_available
    test "returns Epub.Bupe for application/epub+zip" do
      assert MetadataExtractors.find_for("application/epub+zip") == MetadataExtractors.Epub.Bupe
    end

    test "returns nil for an unrecognized type" do
      assert MetadataExtractors.find_for("application/json") == nil
    end
  end
end
