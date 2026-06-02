defmodule Attached.Processors.MetadataExtractors do
  @moduledoc """
  Registry and dispatch for original metadata extractors.

  After an original is created, `Attached.Originals.ExtractMetadataWorker`
  runs the first accepting extractor and merges the result into
  `original.metadata`.

  Each module wraps exactly one tool. Multiple modules can target the
  same content type — the dispatcher picks the first one whose binary
  (or NIF) is available.

  Ships with:
  - `Attached.Processors.MetadataExtractors.Image.Vix` — width, height via libvips (`vix` NIF)
  - `Attached.Processors.MetadataExtractors.Image.ImageMagick` — width, height via `identify`
  - `Attached.Processors.MetadataExtractors.Video.FFmpeg` — width, height, duration, angle, aspect ratio, audio/video flags
  - `Attached.Processors.MetadataExtractors.Audio.FFmpeg` — duration, bit_rate
  - `Attached.Processors.MetadataExtractors.Epub.Bupe` — Dublin Core metadata via the `bupe` package

  ## Configuration

      config :attached, metadata_extractors: [
        Attached.Processors.MetadataExtractors.Image.Vix,
        Attached.Processors.MetadataExtractors.Video.FFmpeg,
        Attached.Processors.MetadataExtractors.Audio.FFmpeg,
        MyApp.MetadataExtractors.Office
      ]
  """

  @doc """
  Returns the first extractor that accepts the given content type and
  whose runtime dependencies are available. `nil` if none match.
  """
  def find_for(content_type) do
    Enum.find(list(), fn mod -> mod.accept?(content_type) and mod.available?() end)
  end

  @doc "Returns all configured extractors (regardless of availability)."
  def list do
    Application.get_env(:attached, :metadata_extractors, [
      Attached.Processors.MetadataExtractors.Image.Vix,
      Attached.Processors.MetadataExtractors.Image.ImageMagick,
      Attached.Processors.MetadataExtractors.Video.FFmpeg,
      Attached.Processors.MetadataExtractors.Audio.FFmpeg,
      Attached.Processors.MetadataExtractors.Epub.Bupe
    ])
  end
end
