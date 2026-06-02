defmodule Attached.Originals.Scopes do
  @moduledoc """
  Composable query scopes for `Attached.Originals.Original`.

  Each scope takes a query (or the `Original` schema) and returns a refined query.
  Designed for the `:query` hook in `Attached.Originals.list/1` and `Attached.Originals.count/1`:

      Attached.Originals.list(
        query: &Attached.Originals.Scopes.orphans(&1, "users", "avatar_attached_original_id")
      )
  """

  import Ecto.Query

  @doc """
  Restricts a query to originals belonging to a specific `(owner_table, owner_field)` group.
  """
  def by_owner(query, owner_table, owner_field)
      when is_binary(owner_table) and is_binary(owner_field) do
    from(b in query,
      where: b.owner_table == ^owner_table and b.owner_field == ^owner_field
    )
  end

  @doc """
  Restricts a query to orphaned originals within a single `(owner_table, owner_field)` group.

  An original is orphaned when no row in `owner_table` references it via the
  `owner_field` column. The group is required because SQL identifiers
  (table/column names) can't be bound per row — iterate
  `Attached.Originals.list_owner_groups/0` to cover every group.
  """
  def orphans(query, owner_table, owner_field)
      when is_binary(owner_table) and is_binary(owner_field) do
    query
    |> by_owner(owner_table, owner_field)
    |> where(
      [b],
      fragment(
        "NOT EXISTS (SELECT 1 FROM ? WHERE ? = ?)",
        literal(^owner_table),
        literal(^owner_field),
        b.id
      )
    )
  end
end
