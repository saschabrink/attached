defmodule Attached.Originals.Stats do
  @moduledoc """
  Aggregate statistics over `attached_originals`.

  Intended for dashboards and scripts. If you need raw counts with custom
  scopes, use `Attached.Originals.count/1` with a `:query` hook instead.
  """

  import Ecto.Query

  alias Attached.Originals.Original

  @doc """
  Top-level summary of original storage.

      %{record_count: 12_453, total_bytes: 9_812_441_103}
  """
  def overview do
    from(b in Original,
      select: %{
        record_count: count(b.id),
        total_bytes: coalesce(sum(b.byte_size), 0)
      }
    )
    |> Attached.Repo.current().one()
  end

  @doc """
  Original counts grouped by major MIME type, sorted by count descending.

      [
        %{type: "image", record_count: 9_102},
        %{type: "video", record_count: 2_841},
        %{type: "application", record_count: 510}
      ]

  Groups by the major type (the part before the `/` in the content type), so
  `image/png`, `image/jpeg`, and `image/webp` all map to `"image"`.
  """
  def by_content_type do
    from(b in Original,
      group_by: b.content_type,
      select: %{content_type: b.content_type, record_count: count(b.id)}
    )
    |> Attached.Repo.current().all()
    |> Enum.group_by(fn %{content_type: ct} -> ct |> String.split("/") |> hd() end)
    |> Enum.map(fn {type, entries} ->
      %{type: type, record_count: entries |> Enum.map(& &1.record_count) |> Enum.sum()}
    end)
    |> Enum.sort_by(& &1.record_count, :desc)
  end

  @doc """
  Per-group original statistics as
  `[%{owner_table, owner_field, original_count, total_bytes}]`, sorted by
  count descending.
  """
  def by_owner_group do
    from(b in Original,
      group_by: [b.owner_table, b.owner_field],
      select: %{
        owner_table: b.owner_table,
        owner_field: b.owner_field,
        original_count: count(b.id),
        total_bytes: coalesce(sum(b.byte_size), 0)
      },
      order_by: [desc: count(b.id)]
    )
    |> Attached.Repo.current().all()
  end

  @doc """
  Original counts and size aggregates grouped by storage backend.

  The `storage_backend` column records the backend's instance name from the
  `config :attached, :storage_backends` registry.

      [
        %{
          storage_backend: "s3_main",
          record_count: 11_203,
          total_bytes: 9_700_000_000,
          avg_bytes: 865_848,
          max_bytes: 524_288_000
        }
      ]
  """
  def by_storage_backend do
    from(b in Original,
      group_by: b.storage_backend,
      select: %{
        storage_backend: b.storage_backend,
        record_count: count(b.id),
        total_bytes: coalesce(sum(b.byte_size), 0),
        avg_bytes: avg(b.byte_size),
        max_bytes: max(b.byte_size)
      }
    )
    |> Attached.Repo.current().all()
  end
end
