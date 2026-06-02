defmodule Attached.Originals.ContentType do
  @moduledoc """
  Detects the real content type of a file by reading its magic bytes.

  Used by `Attached.Originals` during ingest to override the caller-supplied
  content type with the actual file type. Falls back to the supplied value
  when the magic bytes are unrecognized.

  ## Configuration

      # Disable automatic detection (not recommended):
      config :attached, identify_content_type: false
  """

  @doc """
  Reads up to 16 bytes from `path` and returns the detected MIME type,
  or `fallback` if the file cannot be read or the type is unrecognized.

  Returns `fallback` without reading when
  `config :attached, identify_content_type: false` is set.
  """
  def detect(path, fallback \\ "application/octet-stream") do
    if Application.get_env(:attached, :identify_content_type, true) do
      from_file(path, fallback)
    else
      fallback
    end
  end

  defp from_file(path, fallback) do
    case :file.open(path, [:read, :binary]) do
      {:ok, fd} ->
        try do
          case :file.read(fd, 16) do
            {:ok, bytes} -> from_magic(bytes, fallback)
            _ -> fallback
          end
        after
          :file.close(fd)
        end

      _ ->
        fallback
    end
  end

  # Images
  defp from_magic(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>, _), do: "image/png"
  defp from_magic(<<0xFF, 0xD8, 0xFF, _::binary>>, _), do: "image/jpeg"
  defp from_magic(<<"GIF87a", _::binary>>, _), do: "image/gif"
  defp from_magic(<<"GIF89a", _::binary>>, _), do: "image/gif"
  defp from_magic(<<"RIFF", _::32, "WEBP", _::binary>>, _), do: "image/webp"
  defp from_magic(<<"BM", _::binary>>, _), do: "image/bmp"
  # TIFF little-endian and big-endian
  defp from_magic(<<0x49, 0x49, 0x2A, 0x00, _::binary>>, _), do: "image/tiff"
  defp from_magic(<<0x4D, 0x4D, 0x00, 0x2A, _::binary>>, _), do: "image/tiff"

  # Documents
  defp from_magic(<<"%PDF", _::binary>>, _), do: "application/pdf"
  # ZIP magic — but honour a caller-supplied subtype (e.g. application/epub+zip)
  # since magic bytes alone can't distinguish ZIP subtypes.
  defp from_magic(<<"PK", 0x03, 0x04, _::binary>>, "application/octet-stream"),
    do: "application/zip"

  defp from_magic(<<"PK", 0x03, 0x04, _::binary>>, fallback), do: fallback

  # Audio
  defp from_magic(<<"ID3", _::binary>>, _), do: "audio/mpeg"
  defp from_magic(<<0xFF, 0xFB, _::binary>>, _), do: "audio/mpeg"
  defp from_magic(<<0xFF, 0xF3, _::binary>>, _), do: "audio/mpeg"
  defp from_magic(<<0xFF, 0xF2, _::binary>>, _), do: "audio/mpeg"
  defp from_magic(<<"OggS", _::binary>>, _), do: "audio/ogg"
  defp from_magic(<<"fLaC", _::binary>>, _), do: "audio/flac"
  defp from_magic(<<"RIFF", _::32, "WAVE", _::binary>>, _), do: "audio/wav"

  # Video
  defp from_magic(<<"RIFF", _::32, "AVI ", _::binary>>, _), do: "video/x-msvideo"
  # WebM / MKV — EBML header
  defp from_magic(<<0x1A, 0x45, 0xDF, 0xA3, _::binary>>, _), do: "video/webm"
  # ISO base media (MP4, MOV, M4A, AVIF, HEIC, HEIF): ftyp box at byte offset 4.
  # AVIF and HEIC reuse the MP4 container, so we have to dispatch on the brand
  # to avoid mis-tagging still images as video/mp4.
  defp from_magic(<<_::32, "ftyp", brand::binary-size(4), _::binary>>, _) do
    case brand do
      "M4A " -> "audio/mp4"
      "M4B " -> "audio/mp4"
      "qt  " -> "video/quicktime"
      "avif" -> "image/avif"
      "avis" -> "image/avif"
      "heic" -> "image/heic"
      "heix" -> "image/heic"
      "heim" -> "image/heif"
      "heis" -> "image/heif"
      "mif1" -> "image/heif"
      "msf1" -> "image/heif"
      _ -> "video/mp4"
    end
  end

  defp from_magic(_, fallback), do: fallback
end
