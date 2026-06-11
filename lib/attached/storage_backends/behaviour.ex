defmodule Attached.StorageBackends.Behaviour do
  @moduledoc """
  Behaviour contract for storage backends.

  A backend is a named instance in the registry — a `{module, config}` pair
  under `config :attached, :storage_backends` (see `Attached.StorageBackends`).
  Every callback receives that instance's config keyword list as its first
  argument: backend modules hold no global state, so the same module can back
  several named instances (e.g. two S3 buckets).

  Callers should not use backend modules directly — go through
  `Attached.StorageBackends`, which resolves the default instance and
  dispatches with its config.
  """

  @type key :: String.t()
  @type config :: keyword()

  @doc "Upload a file from `source_path` to the given `key`."
  @callback upload(config, key, source_path :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc "Download the file at `key` and return its binary content."
  @callback download(config, key) :: {:ok, binary()} | {:error, term()}

  @doc "Return the partial content in the byte `range` of the file at `key`."
  @callback download_chunk(config, key, Range.t()) :: {:ok, binary()} | {:error, term()}

  @doc "Concatenate files at `source_keys` into a single file at `destination_key`."
  @callback compose(config, source_keys :: [key], destination_key :: key) ::
              :ok | {:error, term()}

  @doc "Delete the file at `key`."
  @callback delete(config, key) :: :ok | {:error, term()}

  @doc "Delete files at keys starting with the `prefix`."
  @callback delete_prefixed(config, prefix :: String.t()) :: :ok | {:error, term()}

  @doc "Return `true` if a file exists at `key`."
  @callback exists?(config, key) :: boolean()

  @doc "Return a URL for the file at `key`."
  @callback url(config, key, opts :: keyword()) :: String.t()

  @doc """
  Return a URL (plus the headers the client must send) for uploading the file
  at `key` directly from the browser via HTTP PUT.

  Options: `:content_type`, `:checksum` (base64 MD5, pinned via
  `Content-MD5`), `:byte_size` (pinned via `Content-Length`), `:expires_in`.

  Optional — backends that cannot offer direct uploads simply don't implement
  it; `Attached.StorageBackends.direct_upload_url/2` then returns
  `{:error, :not_supported}`.
  """
  @callback direct_upload_url(config, key, opts :: keyword()) ::
              {:ok, %{url: String.t(), headers: [{String.t(), String.t()}]}} | {:error, term()}

  @optional_callbacks direct_upload_url: 3
end
