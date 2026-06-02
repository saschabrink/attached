defmodule Attached.Processors.ImagePreviewers do
  @moduledoc """
  Registry and dispatch for image previewers.

  An image previewer accepts a content type and a system tool, checks at runtime
  whether the tool is available, and renders a preview image.

  Each module wraps exactly one CLI tool. Multiple modules can target the
  same content type — the dispatcher picks the first one whose binary is
  installed, so installing any of them is enough.

  Ships with:
  - `Attached.Processors.ImagePreviewers.Video.FFmpeg` — extracts first frame via `ffmpeg`
  - `Attached.Processors.ImagePreviewers.Pdf.Pdftoppm` — renders first page via `pdftoppm` (poppler)
  - `Attached.Processors.ImagePreviewers.Pdf.Mutool` — renders first page via `mutool` (MuPDF)
  - `Attached.Processors.ImagePreviewers.Epub.EpubThumbnailer` — extracts cover via `epub-thumbnailer` (Nix)
  - `Attached.Processors.ImagePreviewers.Epub.GnomeEpubThumbnailer` — extracts cover via `gnome-epub-thumbnailer` (apt)

  ## Configuration

  Image previewers are tried in order. Override the list to add your own or
  reorder fallbacks:

      config :attached, image_previewers: [
        Attached.Processors.ImagePreviewers.Video.FFmpeg,
        Attached.Processors.ImagePreviewers.Pdf.Mutool,
        Attached.Processors.ImagePreviewers.Pdf.Pdftoppm,
        MyApp.ImagePreviewers.Office
      ]
  """

  @doc """
  Returns the first image previewer that accepts the given content type and
  whose runtime dependencies are available. `nil` if none match.
  """
  def find_for(content_type) do
    Enum.find(list(), fn mod -> mod.accept?(content_type) and mod.available?() end)
  end

  @doc "Returns all configured image previewers (regardless of availability)."
  def list do
    Application.get_env(:attached, :image_previewers, [
      Attached.Processors.ImagePreviewers.Video.FFmpeg,
      Attached.Processors.ImagePreviewers.Pdf.Pdftoppm,
      Attached.Processors.ImagePreviewers.Pdf.Mutool,
      Attached.Processors.ImagePreviewers.Epub.EpubThumbnailer,
      Attached.Processors.ImagePreviewers.Epub.GnomeEpubThumbnailer
    ])
  end
end
