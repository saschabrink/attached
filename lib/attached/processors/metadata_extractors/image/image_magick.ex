defmodule Attached.Processors.MetadataExtractors.Image.ImageMagick do
  @moduledoc """
  Extracts width and height from image files using the ImageMagick
  `identify` CLI. Swaps dimensions for images rotated 90°/270° via EXIF.
  """

  @behaviour Attached.Processors.MetadataExtractors.Behaviour

  @image_types ~w(image/png image/jpeg image/gif image/webp image/tiff
                  image/bmp image/heic image/heif image/avif)

  @impl true
  def accept?(content_type), do: content_type in @image_types

  @impl true
  def available?, do: not is_nil(System.find_executable("identify"))

  @impl true
  def install_hint do
    "Install ImageMagick: `brew install imagemagick`, `apt install imagemagick`, or `nix-shell -p imagemagick`. The `identify` CLI must be on PATH."
  end

  @impl true
  def metadata(input_path) do
    if not File.exists?(input_path) do
      %{}
    else
      metadata_from_file(input_path)
    end
  end

  defp metadata_from_file(input_path) do
    try do
      case System.cmd("identify", ["-format", "%w %h %[EXIF:Orientation]", input_path]) do
        {output, 0} ->
          case String.split(String.trim(output)) do
            [w, h | rest] ->
              orientation = List.first(rest)
              angle = exif_orientation_to_angle(orientation)
              {w, _} = Integer.parse(w)
              {h, _} = Integer.parse(h)
              if angle in [90, 270], do: %{width: h, height: w}, else: %{width: w, height: h}

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    rescue
      ErlangError -> %{}
    end
  end

  # EXIF orientation values 5–8 indicate 90/270° rotation
  defp exif_orientation_to_angle(orientation) do
    case orientation do
      o when o in ["5", "6"] -> 90
      o when o in ["7", "8"] -> 270
      _ -> 0
    end
  end
end
