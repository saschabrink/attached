defmodule Attached.Processors.MetadataExtractors.Image.ImageMagickTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.MetadataExtractors.Image.ImageMagick

  @fixture_with_exif Path.expand("../../../../support/fixtures/header_with_exif.jpg", __DIR__)
  @available not is_nil(System.find_executable("identify"))

  describe "accept?/1" do
    test "returns true for image content types" do
      assert ImageMagick.accept?("image/png")
      assert ImageMagick.accept?("image/jpeg")
      assert ImageMagick.accept?("image/gif")
      assert ImageMagick.accept?("image/webp")
    end

    test "returns false for non-image content types" do
      refute ImageMagick.accept?("video/mp4")
      refute ImageMagick.accept?("audio/mpeg")
      refute ImageMagick.accept?("application/pdf")
    end
  end

  describe "metadata/1" do
    @tag skip: not @available
    test "extracts width and height from a JPEG with EXIF" do
      assert ImageMagick.metadata(@fixture_with_exif) == %{width: 1, height: 1}
    end

    @tag skip: not @available
    test "returns a map with integer dimensions" do
      meta = ImageMagick.metadata(@fixture_with_exif)
      assert is_integer(meta[:width])
      assert is_integer(meta[:height])
    end

    @tag skip: not @available
    test "returns empty map for nonexistent path" do
      assert ImageMagick.metadata("/nonexistent/image.png") == %{}
    end
  end
end
