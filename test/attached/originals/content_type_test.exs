defmodule Attached.Originals.ContentTypeTest do
  use ExUnit.Case, async: true

  @fixture_png Path.expand("../../support/fixtures/header.png", __DIR__)

  defp tmp(content) do
    path = Path.join(System.tmp_dir!(), "ct_test_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  describe "detect/2" do
    test "detects PNG" do
      assert Attached.Originals.ContentType.detect(@fixture_png) == "image/png"
    end

    test "detects JPEG" do
      path = tmp(<<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, "JFIF", 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/jpeg"
    end

    test "detects GIF89a" do
      path = tmp("GIF89a" <> <<0x01, 0x00, 0x01, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/gif"
    end

    test "detects GIF87a" do
      path = tmp("GIF87a" <> <<0x01, 0x00, 0x01, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/gif"
    end

    test "detects WebP" do
      path = tmp("RIFF" <> <<0x00, 0x00, 0x00, 0x00>> <> "WEBP")
      assert Attached.Originals.ContentType.detect(path) == "image/webp"
    end

    test "detects PDF" do
      path = tmp("%PDF-1.4 header")
      assert Attached.Originals.ContentType.detect(path) == "application/pdf"
    end

    test "detects ZIP" do
      path = tmp("PK" <> <<0x03, 0x04>> <> "rest of zip")
      assert Attached.Originals.ContentType.detect(path) == "application/zip"
    end

    test "honours caller-supplied ZIP subtype (e.g. EPUB)" do
      path = tmp("PK" <> <<0x03, 0x04>> <> "rest of zip")
      assert Attached.Originals.ContentType.detect(path, "application/epub+zip") == "application/epub+zip"
    end

    test "still returns application/zip when fallback is application/octet-stream" do
      path = tmp("PK" <> <<0x03, 0x04>> <> "rest of zip")
      assert Attached.Originals.ContentType.detect(path, "application/octet-stream") == "application/zip"
    end

    test "detects MP3 (ID3)" do
      path = tmp("ID3" <> <<0x03, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "audio/mpeg"
    end

    test "detects FLAC" do
      path = tmp("fLaC" <> <<0x00, 0x00, 0x00, 0x22>>)
      assert Attached.Originals.ContentType.detect(path) == "audio/flac"
    end

    test "detects MP4 (ftyp isom)" do
      # 4-byte box size + "ftyp" + brand "isom"
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "isom" <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "video/mp4"
    end

    test "detects M4A (ftyp M4A )" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "M4A " <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "audio/mp4"
    end

    test "detects QuickTime MOV (ftyp qt  )" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "qt  " <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "video/quicktime"
    end

    test "detects AVIF (ftyp avif)" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "avif" <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/avif"
    end

    test "detects animated AVIF (ftyp avis)" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "avis" <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/avif"
    end

    test "detects HEIC (ftyp heic)" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "heic" <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/heic"
    end

    test "detects HEIC sequence (ftyp heix)" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "heix" <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/heic"
    end

    test "detects HEIF (ftyp mif1)" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "mif1" <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/heif"
    end

    test "detects HEIF sequence (ftyp msf1)" do
      path = tmp(<<0x00, 0x00, 0x00, 0x18>> <> "ftyp" <> "msf1" <> <<0x00, 0x00, 0x00, 0x00>>)
      assert Attached.Originals.ContentType.detect(path) == "image/heif"
    end

    test "detects WebM (EBML header)" do
      path = tmp(<<0x1A, 0x45, 0xDF, 0xA3, 0x01, 0xFF, 0xFF, 0xFF>>)
      assert Attached.Originals.ContentType.detect(path) == "video/webm"
    end

    test "falls back to supplied value for unknown bytes" do
      path = tmp("completely unknown file content xyz")

      assert Attached.Originals.ContentType.detect(path, "application/octet-stream") ==
               "application/octet-stream"

      assert Attached.Originals.ContentType.detect(path, "text/plain") == "text/plain"
    end

    test "falls back when file does not exist" do
      assert Attached.Originals.ContentType.detect("/nonexistent/path/file.bin", "text/csv") == "text/csv"
    end
  end
end
