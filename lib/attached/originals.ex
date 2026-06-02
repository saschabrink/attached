defmodule Attached.Originals do
  @moduledoc """
  Context module for originals.

  Original-entity-level operations. The top-level `Attached` module exposes a
  record-oriented API (`put_attached/3`, `Attached.purge/2`) that works with
  user schemas and fields; this module exposes the original-id-oriented
  counterparts for dashboards, scripts, and custom tooling.

  All worker enqueues go through this module — the workers themselves
  (`ExtractMetadataWorker`, `PurgeWorker`, `PurgeOrphansWorker`) should
  not be called directly.

  ## Ingestion

  Original ingestion has three entry points, all funneling into the same
  pipeline (store, stat, checksum, insert, enqueue analysis):

    * `create_from_upload!/2` — duck-typed uploads with a `:path` key
      (e.g. `%Plug.Upload{}`, plain maps from Oban jobs).
    * `create_from_file!/2` — a local path on disk.
    * `create_from_stream!/2` — the primitive. Any `Enumerable` of binary
      chunks. Use this when the bytes come from somewhere else (HTTP
      download, S3 copy, binary DB column, in-memory buffer).

  Variant ingestion lives in `Attached.Variants` and writes to the
  `attached_variants` table — see `Attached.Variants.process/3`.

  ## Querying

  `list/1` and `count/1` accept the same composable option set as
  `ecto_context`-generated functions:

      # All originals
      Attached.Originals.list()

  Orphan detection happens per `(owner_table, owner_field)` group, since
  SQL identifiers can't be bound per row. Use `list_owner_groups/0` to iterate
  the distinct groups and `orphans/3` as the filter building block:

      Attached.Originals.list_owner_groups()
      |> Enum.flat_map(fn %{owner_table: table, owner_field: field} ->
        Attached.Originals.list(query: &Scopes.orphans(&1, table, field))
      end)
  """

  import Ecto.Query

  require Logger

  alias Attached.Originals.Original
  alias Attached.Originals.ExtractMetadataWorker
  alias Attached.Originals.PurgeOrphansWorker
  alias Attached.Originals.PurgeWorker
  alias Attached.Originals.Scopes
  alias Attached.Ecto.CRUD

  # ===== CRUD & Workers =====

  @doc """
  Ingests an original file at `path` into storage and inserts the original row.

  This is the original-ingest primitive — `create_from_upload!/2` and
  `create_from_stream!/2` both funnel into it (an upload already has a path
  on disk; a stream gets materialized to a tmp file first).

  Options:
    * `:owner_table` (required)
    * `:owner_field` (required, coerced to string)
    * `:filename` — defaults to `Path.basename(path)`
    * `:content_type` — defaults to `"application/octet-stream"` (refined by
      `Attached.Originals.ContentType` unless disabled)

  Variants go through `Attached.Variants.process/3`, not here.
  """
  def create_from_file!(path, opts) when is_binary(path) do
    owner_table = Keyword.fetch!(opts, :owner_table)
    owner_field = to_string(Keyword.fetch!(opts, :owner_field))
    filename = Keyword.get(opts, :filename) || Path.basename(path)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    content_type = Attached.Originals.ContentType.detect(path, content_type)

    key = Original.generate_key()

    ingest!(path, key,
      filename: filename,
      content_type: content_type,
      owner_table: owner_table,
      owner_field: owner_field
    )
  end

  # Shared ingest pipeline used by all original-ingestion entry points.
  defp ingest!(path, key, attrs) do
    repo = Attached.Repo.current()

    :ok = Attached.StorageBackends.upload(key, path)
    %{size: byte_size} = File.stat!(path)

    original =
      attrs
      |> Keyword.merge(
        key: key,
        byte_size: byte_size,
        checksum: compute_checksum(path),
        storage_backend: inspect(Attached.StorageBackends.current())
      )
      |> Map.new()
      |> Original.changeset()
      |> repo.insert!()

    extract_metadata_later(original.id)

    original
  end

  @doc """
  Ingests a duck-typed upload (`%Plug.Upload{}`, plain map with `:path`).

  Short-circuits when `upload` is already a `%Attached.Originals.Original{}` — returns
  it unchanged, so callers can accept either fresh uploads or pre-existing
  originals (e.g. re-attaching an original to a new record).

  Pulls `:filename` and `:content_type` from the struct (unless explicitly
  passed) and delegates to `create_from_file!/2`.
  """
  def create_from_upload!(%Original{} = original, _opts), do: original

  def create_from_upload!(upload, opts) do
    {path, filename, content_type} = normalize_upload(upload)

    opts
    |> Keyword.put_new(:filename, filename)
    |> Keyword.put_new(:content_type, content_type)
    |> then(&create_from_file!(path, &1))
  end

  @doc """
  Ingests an `Enumerable` of binary chunks.

  Writes the stream to a tmp file, then delegates to `create_from_file!/2`
  (storage backends need a path for efficient upload). Use this when bytes
  come from a source the other helpers don't cover — HTTP downloads, S3
  copies, in-memory buffers.

  `:filename` is required since there's no path to derive it from.
  """
  def create_from_stream!(stream, opts) do
    Keyword.get(opts, :filename) ||
      raise ArgumentError, "create_from_stream!/2 requires :filename"

    tmp = Path.join(System.tmp_dir!(), "attached-stream-#{Original.generate_key()}")

    try do
      File.open!(tmp, [:write, :binary], fn file ->
        Enum.each(stream, &IO.binwrite(file, &1))
      end)

      create_from_file!(tmp, opts)
    after
      File.rm(tmp)
    end
  end

  @doc """
  Returns originals matching the given options.

  ## Options

    * `:preload` — associations to preload
    * `:order_by` — passed to `Ecto.Query.order_by/2`
    * `:limit` — max results
    * `:offset` — number of rows to skip (for pagination with `:limit`)
    * `:select` — list of fields to select
    * `:distinct` — field atom; returns distinct values of that field
      (implies `select`, `distinct`, and `order_by` on the field). Useful
      for filter-dropdown lookups.
    * `:exclude_nil` — when `true` together with `:distinct`, filters out
      rows where the distinct field is `nil`.
    * `:query` — 1-arity function for additional composition, e.g.
      `&Scopes.orphans(&1, "users", "avatar_attached_original_id")`
  """
  def list(opts \\ []), do: CRUD.list(Original, opts)

  @doc """
  Returns the distinct `%{owner_table, owner_field}` pairs across all originals.

  Use this to drive per-group orphan sweeps (see `Scopes.orphans/3`).
  """
  def list_owner_groups do
    list(distinct: [:owner_table, :owner_field])
  end

  @doc """
  Fetches an original by `id`. Returns `nil` if not found.

  ## Options

    * `:preload` — associations to preload
    * `:query` — 1-arity function for additional composition
  """
  def get(id, opts \\ []), do: CRUD.get(Original, id, opts)

  @doc """
  Fetches an original by `id`. Raises `Ecto.NoResultsError` if not found.

  Takes the same options as `get/2`.
  """
  def get!(id, opts \\ []), do: CRUD.get!(Original, id, opts)

  @doc """
  Fetches an original by its storage `key`. Returns `nil` if not found.

  ## Options

    * `:preload` — associations to preload
    * `:query` — 1-arity function for additional composition
  """
  def get_by_key(key, opts \\ []) when is_binary(key) do
    CRUD.get_by(Original, [key: key], opts)
  end

  @doc """
  Looks up the owner row that references this original.

  Queries `original.owner_table` for a row whose `original.owner_field` equals
  `original.id` and returns it as a plain map. Returns `nil` if no such row
  exists, or if `owner_field` is not a real column on `owner_table`
  (e.g. legacy rows pointing at a removed field).
  """
  def get_owner(%Original{owner_table: table, owner_field: field, id: id}) do
    repo = Attached.Repo.current()
    placeholder = if repo.__adapter__() == Ecto.Adapters.Postgres, do: "$1", else: "?"
    sql = ~s(SELECT * FROM "#{table}" WHERE "#{field}" = #{placeholder} LIMIT 1)

    case Ecto.Adapters.SQL.query(repo, sql, [id]) do
      {:ok, %{columns: cols, rows: [row]}} ->
        cols |> Enum.zip(row) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Counts originals matching the given options.

  Accepts the same `:query` hook as `list/1`.
  """
  def count(opts \\ []), do: CRUD.count(Original, opts)

  @doc """
  Paginates originals with the same `:query`/`:order_by`/`:preload`/`:select`
  options as `list/1`, plus:

    * `:page` — 1-based page number (default `1`)
    * `:per_page` — items per page (default `25`)

  Returns a map `%{entries: [...], total: n, page: p, per_page: pp}`.
  """
  def paginate(opts \\ []), do: CRUD.paginate(Original, opts)

  @doc """
  Merges `metadata` into `original.metadata` and persists it.
  """
  def update_metadata!(%Original{} = original, metadata) when is_map(metadata) do
    original
    |> Ecto.Changeset.change(metadata: Map.merge(original.metadata, metadata))
    |> Attached.Repo.current().update!()
  end

  @doc """
  Enqueues a job to extract metadata from an original asynchronously.

  Runs the first accepting `Attached.Processors.MetadataExtractors` module
  against the original and merges the extracted fields into `original.metadata` —
  e.g. `width`/`height` for images, `duration`/`bit_rate` for audio,
  `width`/`height`/`duration`/`angle`/`aspect_ratio`/`audio`/`video` for
  video. The MIME type is not touched (that's set at ingest time by
  `Attached.Originals.ContentType`).

  Called automatically from `ingest!/4` after insert; safe to re-enqueue
  by hand (e.g. after adding a new extractor).
  """
  def extract_metadata_later(original_id) do
    %{original_id: original_id} |> ExtractMetadataWorker.new() |> Oban.insert()
  end

  @doc """
  Synchronously deletes an original, its variants, and all associated storage files.

  Cascades to `Attached.Variants.delete_for!/1` for the variant cleanup,
  then deletes the original row and its storage object.

  Accepts either a `%Original{}` struct or an original id — the id form loads the
  original first and is a no-op if it no longer exists.
  """
  def purge!(nil), do: :ok
  def purge!(original_id) when is_binary(original_id), do: original_id |> get() |> purge!()

  def purge!(%Original{} = original) do
    repo = Attached.Repo.current()

    Attached.Variants.delete_for!(original)
    repo.delete!(original)
    Attached.StorageBackends.delete(original.key)

    :ok
  end

  @doc """
  Enqueues a job to purge an original asynchronously. Accepts a `%Original{}` or its id.
  """
  def purge_later(%Original{id: id}), do: purge_later(id)

  def purge_later(original_id) when is_binary(original_id) do
    %{original_id: original_id} |> PurgeWorker.new() |> Oban.insert()
  end

  @doc """
  Enqueues a scan-and-purge pass over all orphaned originals.
  """
  def purge_orphans_later do
    %{} |> PurgeOrphansWorker.new() |> Oban.insert()
  end

  @doc """
  Enqueues purge jobs for all orphaned originals in a specific `(owner_table, owner_field)` group.

  Useful when you want to clean up a single group rather than all orphans at once:

      Attached.Originals.purge_by_owner_group("users", "avatar_attached_original_id")
  """
  def purge_by_owner_group(owner_table, owner_field)
      when is_binary(owner_table) and is_binary(owner_field) do
    list(query: &Scopes.orphans(&1, owner_table, owner_field))
    |> Enum.each(&purge_later/1)
  end

  @doc """
  Total count of orphaned originals across every `(owner_table, owner_field)` group.

  Groups whose `owner_field` is not a real column on `owner_table` are skipped
  (with a `Logger.warning/1`) rather than raising.
  """
  def count_orphans do
    list_orphan_groups() |> Enum.reduce(0, &(&2 + &1.orphan_count))
  end

  @doc """
  Counts orphaned originals within a single `(owner_table, owner_field)` group.

  Returns `0` and logs a warning if `owner_field` is not a real column on
  `owner_table`.
  """
  def count_orphans(owner_table, owner_field)
      when is_binary(owner_table) and is_binary(owner_field) do
    safe_orphan_run(owner_table, owner_field, 0, fn ->
      count(query: &Scopes.orphans(&1, owner_table, owner_field))
    end)
  end

  @doc """
  Lists orphaned originals within a single `(owner_table, owner_field)` group,
  ordered by `inserted_at` descending.

  Returns `[]` and logs a warning if `owner_field` is not a real column on
  `owner_table`.
  """
  def list_orphans(owner_table, owner_field, limit \\ nil, offset \\ nil)
      when is_binary(owner_table) and is_binary(owner_field) do
    safe_orphan_run(owner_table, owner_field, [], fn ->
      list(
        query: &Scopes.orphans(&1, owner_table, owner_field),
        order_by: [desc: :inserted_at],
        limit: limit,
        offset: offset
      )
    end)
  end

  @doc """
  Returns orphan summary per group as `[%{owner_table, owner_field, orphan_count, total_bytes}]`.

  Groups with zero orphans are omitted. Groups whose `owner_field` is not a real
  column on `owner_table` are skipped with a `Logger.warning/1`.
  """
  def list_orphan_groups do
    list_owner_groups()
    |> Enum.flat_map(fn %{owner_table: owner_table, owner_field: owner_field} ->
      case orphan_aggregate(owner_table, owner_field) do
        %{count: 0} ->
          []

        %{count: n, total_bytes: bytes} ->
          [
            %{
              owner_table: owner_table,
              owner_field: owner_field,
              orphan_count: n,
              total_bytes: bytes
            }
          ]
      end
    end)
  end

  # ===== Private =====

  defp orphan_aggregate(owner_table, owner_field) do
    safe_orphan_run(owner_table, owner_field, %{count: 0, total_bytes: 0}, fn ->
      from(b in Original)
      |> Scopes.orphans(owner_table, owner_field)
      |> select([b], %{count: count(b.id), total_bytes: coalesce(sum(b.byte_size), 0)})
      |> Attached.Repo.current().one()
    end)
  end

  defp safe_orphan_run(owner_table, owner_field, default, fun) do
    fun.()
  rescue
    e ->
      Logger.warning("[Attached] Skipping orphan group #{owner_table}.#{owner_field}: #{inspect(e)}")

      default
  end

  # Duck-typed normalization: any map with :path (required) works. Matches
  # %Plug.Upload{}, plain maps from Oban jobs, CLI scripts, etc.
  defp normalize_upload(%{path: path} = upload) do
    filename = Map.get(upload, :filename) || Path.basename(path)

    content_type =
      case Map.get(upload, :content_type) do
        ct when is_binary(ct) -> ct
        _ -> "application/octet-stream"
      end

    {path, filename, content_type}
  end

  defp compute_checksum(path) do
    File.stream!(path, 2_048)
    |> Enum.reduce(:crypto.hash_init(:md5), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode64()
  end
end
