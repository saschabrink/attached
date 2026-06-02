defmodule Attached.Processors.Transformers.Document.Pandoc do
  @moduledoc """
  Document-to-markdown transformer using [`pandoc`](https://pandoc.org/).

  Converts EPUB, DOCX, HTML, RTF, FB2, RST, and LaTeX inputs into a
  GitHub-flavored Markdown variant (`text/markdown`).

  Pandoc auto-detects the input format from the file extension. The
  variant pipeline writes the input to a temp file with the original
  extension preserved, so detection works without an explicit `-f` flag.

  Embedded images are not extracted — image references in the output
  point to the original archive's internal paths and will be broken
  links. Use a separate image previewer (e.g. `Epub.EpubThumbnailer`) for
  cover art.
  """

  @behaviour Attached.Processors.Transformers.Behaviour

  @input_types ~w(
    application/epub+zip
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/html
    application/rtf
    application/x-fictionbook+xml
    text/x-rst
    application/x-tex
  )

  @impl true
  def accept?(input, "text/markdown"), do: input in @input_types
  def accept?(_, _), do: false

  @impl true
  def available?, do: not is_nil(System.find_executable("pandoc"))

  @impl true
  def install_hint do
    "Install pandoc: `brew install pandoc`, `apt install pandoc`, or `nix-shell -p pandoc`."
  end

  @impl true
  def transform(input_path, _transforms, output_path) do
    args = ["-t", "gfm", "-o", output_path, input_path]

    try do
      case System.cmd("pandoc", args, stderr_to_stdout: true) do
        {_, 0} ->
          if File.exists?(output_path),
            do: :ok,
            else: {:error, "pandoc produced no output"}

        {out, code} ->
          {:error, "pandoc exited with code #{code}: #{out}"}
      end
    rescue
      ErlangError -> {:error, "pandoc not found"}
    end
  end
end
