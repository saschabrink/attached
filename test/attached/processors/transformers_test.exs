defmodule Attached.Processors.TransformersTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.Transformers

  describe "list/0" do
    test "defaults to all built-in transformers" do
      assert Transformers.list() == [
               Transformers.Image.Vix,
               Transformers.Image.ImageMagick,
               Transformers.Document.Pandoc
             ]
    end
  end

  describe "find_for/2" do
    test "returns Image.Vix for image/* → image/*" do
      assert Transformers.find_for("image/jpeg", "image/png") == Transformers.Image.Vix
    end

    test "returns nil for unsupported pairs" do
      assert Transformers.find_for("audio/mpeg", "audio/ogg") == nil
      assert Transformers.find_for("application/pdf", "text/plain") == nil
    end
  end
end
