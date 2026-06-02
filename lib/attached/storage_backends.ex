defmodule Attached.StorageBackends do
  @moduledoc """
  Facade for the configured storage backend.

  All blob storage access goes through this module — call sites should
  use `upload/3`, `download/1`, etc. rather than looking up the backend
  and dispatching manually.

  Implement `Attached.StorageBackends.Behaviour` to add a new backend
  and set `config :attached, :storage_backend, MyBackend`. Ships with
  `Attached.StorageBackends.Disk` for local filesystem storage.
  """

  @doc "Returns the configured storage backend module."
  def current do
    Application.get_env(:attached, :storage_backend, Attached.StorageBackends.Disk)
  end

  def upload(key, source_path, opts \\ []), do: current().upload(key, source_path, opts)
  def download(key), do: current().download(key)
  def download_chunk(key, range), do: current().download_chunk(key, range)
  def compose(source_keys, destination_key), do: current().compose(source_keys, destination_key)
  def delete(key), do: current().delete(key)
  def delete_prefixed(prefix), do: current().delete_prefixed(prefix)
  def exists?(key), do: current().exists?(key)
  def url(key, opts \\ []), do: current().url(key, opts)
end
