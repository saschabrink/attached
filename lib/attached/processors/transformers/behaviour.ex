defmodule Attached.Processors.Transformers.Behaviour do
  @moduledoc """
  Behaviour contract for variant transformers.

  Implementations are dispatched by `Attached.Processors.Transformers`
  based on `(input_content_type, output_content_type)` pairs — an image
  transformer declares image/* → image/*, a PDF-to-text transformer
  declares application/pdf → text/plain, etc.
  """

  @doc "Returns true if this transformer can handle the given input/output content-type pair."
  @callback accept?(input_content_type :: String.t(), output_content_type :: String.t()) ::
              boolean()

  @doc """
  Returns true if this transformer's runtime dependencies are present
  (NIF compiled, CLI tool on PATH, etc.). Unavailable transformers are
  skipped by the dispatcher, so the next one in the list can try.
  """
  @callback available?() :: boolean()

  @doc """
  Returns a short, actionable string explaining how to satisfy this
  transformer's runtime dependencies — hex deps to add, system packages
  to install, binaries to provide on PATH.

  Shown in the dashboard for every transformer (not only unavailable
  ones) so operators can use the list as an install checklist.
  """
  @callback install_hint() :: String.t()

  @doc """
  Transform the file at `input_path`, applying `transforms` in order,
  and write the result to `output_path`.
  """
  @callback transform(
              input_path :: String.t(),
              transforms :: keyword(),
              output_path :: String.t()
            ) :: :ok | {:error, term()}
end
