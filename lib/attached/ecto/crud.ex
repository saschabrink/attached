defmodule Attached.Ecto.CRUD do
  @moduledoc """
  Internal, schema-agnostic CRUD helpers used by Attached's context modules.

  Generic query plumbing — `list`, `get`, `get_by`, `count`, `paginate` —
  extracted so context modules stay focused on domain operations (ingest,
  purge, orphan detection, owner lookups).

  Repo resolution goes through `Attached.Repo.current()`. This module is
  not a generic Ecto CRUD package — it's an internal noise-reduction
  pass. If you need a reusable equivalent, see `ecto_context`.

  ## Composable options

  Every function whitelists the options it accepts and raises
  `ArgumentError` on unknown keys. The supported set across all
  functions:

    * `:preload` — associations to preload
    * `:order_by` — passed to `Ecto.Query.order_by/2`
    * `:limit` / `:offset` — pagination primitives
    * `:select` — list of fields to select
    * `:distinct` — atom or list of atoms; turns the query into a
      distinct-field projection (see `maybe_distinct/2` below)
    * `:exclude_nil` — when `true` together with `:distinct` (atom form),
      filters out rows where that field is `nil`
    * `:query` — 1-arity function for ad-hoc query composition, e.g.
      `&Scopes.orphans(&1, "users", "avatar_attached_original_id")`
    * `:page` / `:per_page` — `paginate/2` only

  The `:query` option is the escape hatch: any
  `Ecto.Queryable.t() -> Ecto.Queryable.t()` function gets threaded
  through, so callers can compose library-provided scopes with their
  own slicing.
  """

  import Ecto.Query

  @doc """
  Returns rows of `schema` matching the given options.

  See the module doc for the supported option set.
  """
  def list(schema, opts \\ []) do
    validate_opts!(opts, [:preload, :order_by, :limit, :offset, :select, :distinct, :exclude_nil, :query])

    schema
    |> maybe_query(opts[:query])
    |> maybe_exclude_nil(opts[:distinct], opts[:exclude_nil])
    |> maybe_preload(opts[:preload])
    |> maybe_order_by(opts[:order_by])
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> maybe_select(opts[:select])
    |> maybe_distinct(opts[:distinct])
    |> Attached.Repo.current().all()
  end

  @doc """
  Fetches a row of `schema` by `id`. Returns `nil` if not found.

  Supports `:preload` and `:query`.
  """
  def get(schema, id, opts \\ []) do
    validate_opts!(opts, [:preload, :query])

    schema
    |> maybe_query(opts[:query])
    |> maybe_preload(opts[:preload])
    |> Attached.Repo.current().get(id)
  end

  @doc """
  Fetches a row of `schema` by `id`. Raises `Ecto.NoResultsError` if not found.

  Supports `:preload` and `:query`.
  """
  def get!(schema, id, opts \\ []) do
    validate_opts!(opts, [:preload, :query])

    schema
    |> maybe_query(opts[:query])
    |> maybe_preload(opts[:preload])
    |> Attached.Repo.current().get!(id)
  end

  @doc """
  Fetches a row of `schema` by the given keyword `clauses`. Returns `nil` if not found.

  Supports `:preload` and `:query`.
  """
  def get_by(schema, clauses, opts \\ []) do
    validate_opts!(opts, [:preload, :query])

    schema
    |> maybe_query(opts[:query])
    |> maybe_preload(opts[:preload])
    |> Attached.Repo.current().get_by(clauses)
  end

  @doc """
  Counts rows of `schema` matching the given options.

  Accepts the same `:query` hook as `list/2`.
  """
  def count(schema, opts \\ []) do
    validate_opts!(opts, [:query])

    schema
    |> maybe_query(opts[:query])
    |> select([b], count(b.id))
    |> Attached.Repo.current().one()
  end

  @doc """
  Paginates rows of `schema`.

  Accepts the same `:query`/`:order_by`/`:preload`/`:select` options as
  `list/2`, plus:

    * `:page` — 1-based page number (default `1`)
    * `:per_page` — items per page (default `25`)

  Returns `%{entries: [...], total: n, page: p, per_page: pp}`.
  Internally runs a `count/2` and a `list/2` with `limit` + `offset`
  derived from the page.
  """
  def paginate(schema, opts \\ []) do
    validate_opts!(opts, [:preload, :order_by, :select, :query, :page, :per_page])

    page = max(1, opts[:page] || 1)
    per_page = max(1, opts[:per_page] || 25)
    offset = (page - 1) * per_page

    list_opts =
      opts
      |> Keyword.drop([:page, :per_page])
      |> Keyword.put(:limit, per_page)
      |> Keyword.put(:offset, offset)

    total = count(schema, query: opts[:query])
    entries = list(schema, list_opts)

    %{entries: entries, total: total, page: page, per_page: per_page}
  end

  # ===== Query helpers =====

  @doc "Conditionally preloads associations. No-op when `nil`."
  def maybe_preload(query, nil), do: query
  def maybe_preload(query, associations), do: preload(query, ^associations)

  @doc "Conditionally applies a 1-arity query function. No-op when `nil`."
  def maybe_query(queryable, nil), do: queryable
  def maybe_query(queryable, fun) when is_function(fun, 1), do: fun.(queryable)

  @doc "Conditionally applies an `order_by` clause. No-op when `nil`."
  def maybe_order_by(query, nil), do: query
  def maybe_order_by(query, order_by_clauses), do: order_by(query, ^order_by_clauses)

  @doc "Conditionally applies a `select` clause. No-op when `nil`."
  def maybe_select(query, nil), do: query
  def maybe_select(query, fields) when is_list(fields), do: select(query, ^fields)

  @doc "Conditionally applies a `limit` clause. No-op when `nil`."
  def maybe_limit(query, nil), do: query
  def maybe_limit(query, limit_num) when is_integer(limit_num), do: limit(query, ^limit_num)

  @doc "Conditionally applies an `offset` clause. No-op when `nil`."
  def maybe_offset(query, nil), do: query
  def maybe_offset(query, offset_num) when is_integer(offset_num), do: offset(query, ^offset_num)

  @doc """
  Conditionally filters out rows where `field` is `nil`.

  Pass `true` to apply `WHERE field IS NOT NULL`; anything else is a no-op.
  `field` is an atom column name resolved at runtime.
  """
  def maybe_exclude_nil(query, field, true) when is_atom(field) and not is_nil(field),
    do: where(query, [b], not is_nil(field(b, ^field)))

  def maybe_exclude_nil(query, _field, _), do: query

  @doc """
  Conditionally turns the query into a distinct-field projection.

  Forms:

    * `nil` — no-op.
    * atom — selects that field, applies `DISTINCT`, orders by it
      ascending. Returns scalars. Used for dropdown-style lookups.
    * list of atoms — selects those fields as a map, applies `DISTINCT`,
      orders by them ascending. Returns maps (`%{field: value, ...}`).
      Used when you need distinct tuples of multiple columns.
  """
  def maybe_distinct(query, nil), do: query

  def maybe_distinct(query, field) when is_atom(field) do
    query
    |> select([b], field(b, ^field))
    |> Ecto.Query.distinct(true)
    |> order_by([b], field(b, ^field))
  end

  def maybe_distinct(query, fields) when is_list(fields) do
    query
    |> select([b], map(b, ^fields))
    |> Ecto.Query.distinct(true)
    |> order_by([b], ^Enum.map(fields, &{:asc, &1}))
  end

  @doc """
  Validates that all keys in `opts` are in the `valid_keys` list.

  Raises `ArgumentError` listing unsupported keys.
  """
  def validate_opts!(opts, valid_keys) do
    case Keyword.keys(opts) -- valid_keys do
      [] ->
        :ok

      invalid ->
        raise ArgumentError, """
        Unsupported option(s): #{Enum.map_join(invalid, ", ", &inspect/1)}.
        Supported: #{Enum.map_join(valid_keys, ", ", &inspect/1)}
        """
    end
  end
end
