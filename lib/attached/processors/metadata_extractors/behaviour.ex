defmodule Attached.Processors.MetadataExtractors.Behaviour do
  @moduledoc """
  Behaviour contract for extractors that pull metadata from uploaded files.

  Implementations are dispatched by `Attached.Processors.MetadataExtractors`.
  """

  @doc "Returns true if this extractor can handle the given content type."
  @callback accept?(content_type :: String.t()) :: boolean()

  @doc """
  Returns true if this extractor's runtime dependencies are present
  (NIF compiled, CLI tool on PATH, etc.). Unavailable extractors are
  skipped by the dispatcher, so the next one in the list can try.
  """
  @callback available?() :: boolean()

  @doc """
  Returns a short, actionable string explaining how to satisfy this
  extractor's runtime dependencies — hex deps to add, system packages
  to install, binaries to provide on PATH.

  Shown in the dashboard for every extractor (not only unavailable
  ones) so operators can use the list as an install checklist.
  """
  @callback install_hint() :: String.t()

  @doc """
  Extract metadata from the file at `input_path`.
  Returns a map of metadata to be merged into `original.metadata`.
  """
  @callback metadata(input_path :: String.t()) :: map()
end
