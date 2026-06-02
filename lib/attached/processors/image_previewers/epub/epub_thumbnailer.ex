defmodule Attached.Processors.ImagePreviewers.Epub.EpubThumbnailer do
  @moduledoc """
  Generates a preview image from the cover of an EPUB file using
  [`epub-thumbnailer`](https://github.com/marianosimone/epub-thumbnailer)
  (Python script).

  Available in nixpkgs as `epub-thumbnailer`. Not packaged for
  Debian/Ubuntu — use `Attached.Processors.ImagePreviewers.Epub.GnomeEpubThumbnailer`
  there.
  """

  @behaviour Attached.Processors.ImagePreviewers.Behaviour

  @epub_types ~w(application/epub+zip)
  # Cover is extracted at this longest-edge size; downstream image
  # transformer resizes further if the variant asks for less.
  @native_size 1024

  @impl true
  def accept?(content_type), do: content_type in @epub_types

  @impl true
  def available?, do: not is_nil(System.find_executable("epub-thumbnailer"))

  @impl true
  def install_hint do
    "Install epub-thumbnailer: `nix-shell -p epub-thumbnailer`. " <>
      "Not in apt — on Debian/Ubuntu install `gnome-epub-thumbnailer` instead."
  end

  @impl true
  def preview(input_path, output_path) do
    args = [input_path, output_path, Integer.to_string(@native_size)]

    try do
      case System.cmd("epub-thumbnailer", args, stderr_to_stdout: true) do
        {_, 0} ->
          if File.exists?(output_path),
            do: :ok,
            else: {:error, "epub-thumbnailer produced no output (no cover in EPUB?)"}

        {out, code} ->
          {:error, "epub-thumbnailer exited with code #{code}: #{out}"}
      end
    rescue
      ErlangError -> {:error, "epub-thumbnailer not found"}
    end
  end
end
