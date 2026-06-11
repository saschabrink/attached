defmodule Attached.StorageBackends.Disk do
  @moduledoc """
  Stores files on the local filesystem.

  ## Configuration

      config :attached,
        storage_backends: [
          local: {Attached.StorageBackends.Disk,
            root: Path.join(["priv", "attachments"]),
            base_url: "/attachments"}
        ]

  Instance config keys:

    * `:root` — storage root directory (default `priv/attachments`)
    * `:base_url` — public base URL where `Attached.Web.Plug` is mounted
      (default `"/attachments"`)
  """

  @behaviour Attached.StorageBackends.Behaviour

  @impl true
  def upload(config, key, source_path, _opts \\ []) do
    dest = make_path_for(config, key)
    File.cp!(source_path, dest)
    :ok
  end

  @impl true
  def download(config, key) do
    case File.read(path_for(config, key)) do
      {:ok, _data} = ok -> ok
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def download_chunk(config, key, range) do
    path = path_for(config, key)

    with {:ok, file} <- File.open(path, [:read, :binary]),
         {:ok, _} <- :file.position(file, range.first),
         data = IO.binread(file, Range.size(range)),
         :ok <- File.close(file) do
      {:ok, data}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def compose(config, source_keys, destination_key) do
    dest = make_path_for(config, destination_key)

    File.open!(dest, [:write, :binary], fn out ->
      Enum.each(source_keys, fn key ->
        IO.binwrite(out, File.read!(path_for(config, key)))
      end)
    end)

    :ok
  end

  @impl true
  def delete(config, key) do
    case File.rm(path_for(config, key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_prefixed(config, prefix) do
    base = path_for(config, prefix)
    base = if String.ends_with?(prefix, "/"), do: base <> "/", else: base

    Path.wildcard(base <> "*")
    |> Enum.each(&File.rm_rf!/1)

    :ok
  end

  @impl true
  def exists?(config, key) do
    File.exists?(path_for(config, key))
  end

  @impl true
  def url(config, key, _opts \\ []) do
    "#{base_url(config)}/originals/#{key}"
  end

  @impl true
  def direct_upload_url(config, key, opts \\ []) do
    # Purpose-bound token: a "direct_upload" token is rejected by the GET
    # route and a leaked download token cannot be replayed as a PUT.
    token = Attached.Web.Signer.sign(key, purpose: "direct_upload", expires_in: opts[:expires_in])

    headers =
      [
        {"content-type", opts[:content_type]},
        {"content-md5", opts[:checksum]}
      ]
      |> Enum.reject(fn {_name, value} -> is_nil(value) end)

    {:ok, %{url: "#{base_url(config)}/originals/#{token}", headers: headers}}
  end

  @doc "Returns the absolute filesystem path for a given key."
  def path_for(_config, nil), do: raise(ArgumentError, "key is blank")

  def path_for(config, key) do
    validate_key!(key)
    {folder, filename} = layout_for(key)
    expanded = Path.expand(Path.join([root(config), folder, filename]))
    expanded_root = Path.expand(root(config))

    unless String.starts_with?(expanded, expanded_root <> "/") do
      raise ArgumentError, "key is outside of storage root"
    end

    expanded
  end

  # Two-level directory sharding identical to Active Storage's DiskService.
  # For variant keys (`_variants/<parent_key>-...`), shard on the parent key
  # rather than the `_variants/` namespace so the prefix isn't part of the
  # shard buckets — and drop the namespace from the leaf filename so the
  # `_variants/` segment doesn't appear twice in the path.
  defp layout_for("_variants/" <> rest) do
    {Path.join(["_variants", String.slice(rest, 0, 2), String.slice(rest, 2, 2)]), rest}
  end

  defp layout_for(key) do
    {Path.join([String.slice(key, 0, 2), String.slice(key, 2, 2)]), key}
  end

  defp make_path_for(config, key) do
    path_for(config, key) |> tap(&File.mkdir_p!(Path.dirname(&1)))
  end

  defp validate_key!(key) do
    if is_nil(key) or key == "" do
      raise ArgumentError, "key is blank"
    end

    if String.contains?(key, "\0") do
      raise ArgumentError, "key contains null byte"
    end

    segments = String.split(key, "/")

    if Enum.any?(segments, &(&1 in [".", ".."])) do
      raise ArgumentError, "key contains path traversal segments"
    end
  end

  defp root(config) do
    Keyword.get(config, :root, Path.join(["priv", "attachments"]))
  end

  defp base_url(config) do
    Keyword.get(config, :base_url, "/attachments")
  end
end
