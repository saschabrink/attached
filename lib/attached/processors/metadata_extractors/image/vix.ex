defmodule Attached.Processors.MetadataExtractors.Image.Vix do
  @moduledoc """
  Extracts width and height from image files using libvips via the
  `vix` package. Swaps dimensions for images rotated 90°/270° via EXIF.
  """

  @behaviour Attached.Processors.MetadataExtractors.Behaviour

  @compile {:no_warn_undefined, [Vix.Vips.Image]}

  @image_types ~w(image/png image/jpeg image/gif image/webp image/tiff
                  image/bmp image/heic image/heif image/avif)

  @impl true
  def accept?(content_type), do: content_type in @image_types

  @impl true
  def available?, do: Code.ensure_loaded?(Vix.Vips.Image)

  @impl true
  def install_hint do
    ~s|Add `{:vix, "~> 0.31"}` to mix.exs deps — ships with a precompiled libvips NIF, no system packages needed.|
  end

  @impl true
  def metadata(input_path) do
    case Vix.Vips.Image.new_from_file(input_path) do
      {:ok, image} ->
        w = Vix.Vips.Image.width(image)
        h = Vix.Vips.Image.height(image)
        angle = exif_angle(image)

        if angle in [90, 270],
          do: %{width: h, height: w},
          else: %{width: w, height: h}

      _ ->
        %{}
    end
  end

  defp exif_angle(image) do
    try do
      case Vix.Vips.Image.header_get(image, "exif-ifd0-Orientation") do
        {:ok, val} when val in [5, 6] -> 90
        {:ok, val} when val in [7, 8] -> 270
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end
end
