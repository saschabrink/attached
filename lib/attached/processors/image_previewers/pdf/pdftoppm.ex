defmodule Attached.Processors.ImagePreviewers.Pdf.Pdftoppm do
  @moduledoc """
  Renders the first page of a PDF as a PNG using `pdftoppm` from
  [poppler](https://poppler.freedesktop.org/).
  """

  @behaviour Attached.Processors.ImagePreviewers.Behaviour

  @pdf_types ~w(application/pdf application/x-pdf)

  @impl true
  def accept?(content_type), do: content_type in @pdf_types

  @impl true
  def available?, do: not is_nil(System.find_executable("pdftoppm"))

  @impl true
  def install_hint do
    "Install poppler: `brew install poppler`, `apt install poppler-utils`, or `nix-shell -p poppler_utils`."
  end

  @impl true
  def preview(input_path, output_path) do
    # pdftoppm writes to a path prefix, e.g. /tmp/preview → /tmp/preview-1.png
    # `-singlefile` writes exactly one file without a page-number suffix.
    prefix = String.replace_suffix(output_path, ".png", "")
    args = ["-singlefile", "-r", "72", "-png", input_path, prefix]

    try do
      case System.cmd("pdftoppm", args, stderr_to_stdout: true) do
        {_, 0} ->
          if File.exists?(output_path),
            do: :ok,
            else: {:error, "pdftoppm ran but output file not found at #{output_path}"}

        {out, code} ->
          {:error, "pdftoppm exited with code #{code}: #{out}"}
      end
    rescue
      ErlangError -> {:error, "pdftoppm not found"}
    end
  end
end
