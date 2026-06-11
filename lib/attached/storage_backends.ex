defmodule Attached.StorageBackends do
  @moduledoc """
  Registry and facade for storage backends.

  Backends are named instances: each registry entry pairs a backend module
  with that instance's config. All blob storage access goes through this
  module — call sites use `upload/3`, `download/1`, etc.; the facade resolves
  the default instance and dispatches to its module with its config.

  ## Configuration

      config :attached,
        default_storage_backend: :s3_main,
        storage_backends: [
          local: {Attached.StorageBackends.Disk, root: "priv/attachments"},
          s3_main: {Attached.StorageBackends.S3,
            bucket: "my-bucket",
            region: "eu-central-1",
            access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
            secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")}
        ]

  `:default_storage_backend` may be omitted when exactly one backend is
  configured — it then becomes the default. With no storage configuration at
  all, a `local` Disk instance rooted at `priv/attachments` is used, so
  development works without setup.

  Because the same module can appear under several names (e.g. two S3
  buckets), backends are addressed by name everywhere — including the
  `storage_backend` column on `attached_originals`, which records the
  instance name an original was written to.

  Implement `Attached.StorageBackends.Behaviour` to add a custom backend and
  register it under a name like any built-in.
  """

  @fallback_registry [local: {Attached.StorageBackends.Disk, []}]

  # Pre-0.2 single-backend config keys. If one is present without a registry,
  # the app would silently fall back to local Disk storage (ignoring e.g. an
  # S3 setup) — raise with migration instructions instead.
  @legacy_keys [:storage_backend, :service, :disk, :s3]

  @doc """
  Returns the backend registry: a keyword of `name => {module, config}`
  entries from `config :attached, :storage_backends`.
  """
  def registry do
    case Application.get_env(:attached, :storage_backends) do
      nil ->
        assert_no_legacy_config!()
        @fallback_registry

      entries when is_list(entries) ->
        entries
    end
  end

  @doc """
  Returns the name of the default backend instance.

  `config :attached, :default_storage_backend` when set; otherwise the only
  registry entry. Multiple entries without an explicit default raise —
  registry order must never decide where files go.
  """
  def default_name do
    case Application.get_env(:attached, :default_storage_backend) do
      nil -> infer_default_name()
      name when is_atom(name) -> name
    end
  end

  @doc """
  Resolves a backend instance name to its `{module, config}` pair.

  Raises `ArgumentError` for unknown names or malformed entries.
  """
  def resolve!(name) when is_atom(name) do
    case Keyword.fetch(registry(), name) do
      {:ok, {module, config}} when is_atom(module) and is_list(config) ->
        {module, config}

      {:ok, other} ->
        raise ArgumentError,
              "storage backend #{inspect(name)} must be a `{module, config}` tuple, got: #{inspect(other)}"

      :error ->
        raise ArgumentError,
              "unknown storage backend #{inspect(name)} — configured: #{inspect(Keyword.keys(registry()))}"
    end
  end

  def upload(key, source_path, opts \\ []) do
    {mod, config} = default_backend()
    mod.upload(config, key, source_path, opts)
  end

  def download(key) do
    {mod, config} = default_backend()
    mod.download(config, key)
  end

  def download_chunk(key, range) do
    {mod, config} = default_backend()
    mod.download_chunk(config, key, range)
  end

  def compose(source_keys, destination_key) do
    {mod, config} = default_backend()
    mod.compose(config, source_keys, destination_key)
  end

  def delete(key) do
    {mod, config} = default_backend()
    mod.delete(config, key)
  end

  def delete_prefixed(prefix) do
    {mod, config} = default_backend()
    mod.delete_prefixed(config, prefix)
  end

  def exists?(key) do
    {mod, config} = default_backend()
    mod.exists?(config, key)
  end

  def url(key, opts \\ []) do
    {mod, config} = default_backend()
    mod.url(config, key, opts)
  end

  @doc """
  Returns `{:ok, %{url: url, headers: headers}}` for a direct browser upload
  (HTTP PUT) of `key`, or `{:error, :not_supported}` when the default
  backend doesn't implement the optional `direct_upload_url/3` callback.

  See `Attached.StorageBackends.Behaviour` for the supported options.
  """
  def direct_upload_url(key, opts \\ []) do
    {mod, config} = default_backend()

    if Code.ensure_loaded?(mod) and function_exported?(mod, :direct_upload_url, 3) do
      mod.direct_upload_url(config, key, opts)
    else
      {:error, :not_supported}
    end
  end

  defp default_backend, do: resolve!(default_name())

  defp infer_default_name do
    case registry() do
      [{name, _}] ->
        name

      entries ->
        raise ArgumentError, """
        Multiple storage backends are configured (#{inspect(Keyword.keys(entries))}) \
        but no default is set. Pick one:

            config :attached, :default_storage_backend, #{inspect(entries |> hd() |> elem(0))}
        """
    end
  end

  defp assert_no_legacy_config! do
    case Enum.filter(@legacy_keys, &(Application.get_env(:attached, &1) != nil)) do
      [] ->
        :ok

      keys ->
        raise ArgumentError, """
        Found pre-0.2 storage configuration (#{inspect(keys)}). Storage backends are
        now named instances in a registry:

            config :attached,
              storage_backends: [
                local: {Attached.StorageBackends.Disk, root: "priv/attachments"}
              ]

        Move the old `:disk`/`:s3` keyword into the instance's config tuple and
        delete the `:storage_backend`/`:service` key. See CHANGELOG.md for details.
        """
    end
  end
end
