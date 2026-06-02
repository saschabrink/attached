defmodule Attached.Processors.ImagePreviewers.Epub.GnomeEpubThumbnailer do
  @moduledoc """
  Generates a preview image from the cover of an EPUB file using
  `gnome-epub-thumbnailer` (C tool from the GNOME project, also handles MOBI).

  Packaged for Debian/Ubuntu (`apt install gnome-epub-thumbnailer`) and
  most other distros. Use `Attached.Processors.ImagePreviewers.Epub.EpubThumbnailer`
  on systems where that one is preferred.
  """

  @behaviour Attached.Processors.ImagePreviewers.Behaviour

  @epub_types ~w(application/epub+zip)
  @native_size 1024

  @impl true
  def accept?(content_type), do: content_type in @epub_types

  @impl true
  def available?, do: not is_nil(System.find_executable("gnome-epub-thumbnailer"))

  @impl true
  def install_hint do
    "Install gnome-epub-thumbnailer: `apt install gnome-epub-thumbnailer` " <>
      "(Debian/Ubuntu) or `brew install gnome-epub-thumbnailer`."
  end

  @impl true
  def preview(input_path, output_path) do
    args = ["-s", Integer.to_string(@native_size), input_path, output_path]

    try do
      case System.cmd("gnome-epub-thumbnailer", args, stderr_to_stdout: true) do
        {_, 0} ->
          if File.exists?(output_path),
            do: :ok,
            else: {:error, "gnome-epub-thumbnailer produced no output (no cover in EPUB?)"}

        {out, code} ->
          {:error, "gnome-epub-thumbnailer exited with code #{code}: #{out}"}
      end
    rescue
      ErlangError -> {:error, "gnome-epub-thumbnailer not found"}
    end
  end
end
