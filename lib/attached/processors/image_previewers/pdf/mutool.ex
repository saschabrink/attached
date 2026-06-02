defmodule Attached.Processors.ImagePreviewers.Pdf.Mutool do
  @moduledoc """
  Renders the first page of a PDF as a PNG using `mutool` from
  [MuPDF](https://mupdf.com/).
  """

  @behaviour Attached.Processors.ImagePreviewers.Behaviour

  @pdf_types ~w(application/pdf application/x-pdf)

  @impl true
  def accept?(content_type), do: content_type in @pdf_types

  @impl true
  def available?, do: not is_nil(System.find_executable("mutool"))

  @impl true
  def install_hint do
    "Install mupdf-tools: `brew install mupdf-tools`, `apt install mupdf-tools`, or `nix-shell -p mupdf`."
  end

  @impl true
  def preview(input_path, output_path) do
    # mutool draw -F png -o output.png input.pdf 1
    args = ["draw", "-F", "png", "-o", output_path, input_path, "1"]

    try do
      case System.cmd("mutool", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {out, code} -> {:error, "mutool exited with code #{code}: #{out}"}
      end
    rescue
      ErlangError -> {:error, "mutool not found"}
    end
  end
end
