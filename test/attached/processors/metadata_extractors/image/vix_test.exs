defmodule Attached.Processors.MetadataExtractors.Image.VixTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.MetadataExtractors.Image.Vix

  @fixture_png Path.expand("../../../../support/fixtures/header.png", __DIR__)
  @available Code.ensure_loaded?(Vix)

  describe "accept?/1" do
    test "returns true for image content types" do
      assert Vix.accept?("image/png")
      assert Vix.accept?("image/jpeg")
      assert Vix.accept?("image/gif")
      assert Vix.accept?("image/webp")
    end

    test "returns false for non-image content types" do
      refute Vix.accept?("video/mp4")
      refute Vix.accept?("audio/mpeg")
      refute Vix.accept?("application/pdf")
    end
  end

  describe "metadata/1" do
    @tag skip: not @available
    test "extracts width and height from a PNG" do
      meta = Vix.metadata(@fixture_png)
      assert meta[:width] == 1
      assert meta[:height] == 1
    end

    @tag skip: not @available
    test "returns a map with integer dimensions" do
      meta = Vix.metadata(@fixture_png)
      assert is_integer(meta[:width])
      assert is_integer(meta[:height])
    end

    @tag skip: not @available
    test "returns empty map for unreadable path" do
      meta = Vix.metadata("/nonexistent/image.png")
      assert meta == %{}
    end
  end
end
