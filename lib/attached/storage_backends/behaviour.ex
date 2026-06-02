defmodule Attached.StorageBackends.Behaviour do
  @moduledoc """
  Behaviour contract for storage backends.

  Implement this behaviour to add a new backend. Callers should not
  use the backend module directly — go through `Attached.StorageBackends`
  (which dispatches to the configured backend).
  """

  @type key :: String.t()

  @doc "Upload a file from `source_path` to the given `key`."
  @callback upload(key, source_path :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc "Download the file at `key` and return its binary content."
  @callback download(key) :: {:ok, binary()} | {:error, term()}

  @doc "Return the partial content in the byte `range` of the file at `key`."
  @callback download_chunk(key, Range.t()) :: {:ok, binary()} | {:error, term()}

  @doc "Concatenate files at `source_keys` into a single file at `destination_key`."
  @callback compose(source_keys :: [key], destination_key :: key) :: :ok | {:error, term()}

  @doc "Delete the file at `key`."
  @callback delete(key) :: :ok | {:error, term()}

  @doc "Delete files at keys starting with the `prefix`."
  @callback delete_prefixed(prefix :: String.t()) :: :ok | {:error, term()}

  @doc "Return `true` if a file exists at `key`."
  @callback exists?(key) :: boolean()

  @doc "Return a URL for the file at `key`."
  @callback url(key, opts :: keyword()) :: String.t()
end
