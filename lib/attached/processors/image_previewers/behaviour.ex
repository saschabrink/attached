defmodule Attached.Processors.ImagePreviewers.Behaviour do
  @moduledoc """
  Behaviour contract for image previewers that generate preview images from non-image files.

  Implementations are dispatched by `Attached.Processors.ImagePreviewers`.
  """

  @doc "Returns true if this image previewer handles the given content type."
  @callback accept?(content_type :: String.t()) :: boolean()

  @doc """
  Returns true if this image previewer's runtime dependencies are present
  (NIF compiled, CLI tool on PATH, etc.). Unavailable image previewers are
  skipped by the dispatcher, so the next one in the list can try.
  """
  @callback available?() :: boolean()

  @doc """
  Returns a short, actionable string explaining how to satisfy this
  image previewer's runtime dependencies — hex deps to add, system packages
  to install, binaries to provide on PATH.

  Shown in the dashboard for every image previewer (not only unavailable
  ones) so operators can use the list as an install checklist.
  """
  @callback install_hint() :: String.t()

  @doc """
  Generate a preview image from `input_path` and write it to `output_path`.
  """
  @callback preview(input_path :: String.t(), output_path :: String.t()) ::
              :ok | {:error, term()}
end
