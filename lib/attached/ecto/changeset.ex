defmodule Attached.Ecto.Changeset do
  @moduledoc """
  Changeset integration for `attached` fields.

  Automatically imported into schemas that `use Attached.Ecto.Schema`, so you
  call `put_attached/3` directly inside your `changeset/2` function:

      defmodule MyApp.Accounts.User do
        use Ecto.Schema
        use Attached.Ecto.Schema

        import Ecto.Changeset

        schema "users" do
          field :name, :string
          attached :avatar
          timestamps()
        end

        def changeset(user, attrs) do
          user
          |> cast(attrs, [:name])
          |> put_attached(:avatar, attrs["avatar"])
        end
      end

  The upload is deferred to `prepare_changes/2` so the original insert and
  the storage upload run inside the same transaction as the parent
  insert/update. A failed parent insert rolls the original row back with
  it; the orphaned storage file is swept up by
  `Attached.Originals.PurgeOrphansWorker`.
  """

  @doc """
  Attaches an upload to an `attached` field on the changeset.

  Accepts:
    * `%Plug.Upload{}` structs
    * Maps with `:path` and `:filename` keys (e.g. from
      `Phoenix.LiveView.consume_uploaded_entries/3`)
    * `Attached.Originals.Original` structs (re-attach an existing original —
      no storage I/O, just sets the FK)
    * `nil` — no-op, preserves the existing attachment
  """
  def put_attached(%Ecto.Changeset{} = changeset, _field, nil), do: changeset

  def put_attached(%Ecto.Changeset{} = changeset, field, %Attached.Originals.Original{} = original) do
    fk = fk_for!(changeset, field)
    Ecto.Changeset.put_change(changeset, fk, original.id)
  end

  def put_attached(%Ecto.Changeset{} = changeset, field, upload) do
    schema = changeset.data.__struct__
    fk = fk_for!(changeset, field)

    # Force a change so Ecto doesn't skip the UPDATE when no other fields changed.
    # prepare_changes will overwrite this placeholder with the real original id.
    changeset
    |> Ecto.Changeset.force_change(fk, Map.get(changeset.data, fk))
    |> Ecto.Changeset.prepare_changes(fn changeset ->
      original =
        Attached.Originals.create_from_upload!(upload,
          owner_table: schema.__schema__(:source),
          owner_field: to_string(fk)
        )

      Ecto.Changeset.put_change(changeset, fk, original.id)
    end)
  end

  defp fk_for!(changeset, field) do
    schema = changeset.data.__struct__

    case schema.__attached_config__(field) do
      {^field, opts} ->
        Keyword.fetch!(opts, :foreign_key)

      nil ->
        raise ArgumentError,
              "#{inspect(schema)} does not have an attached field #{inspect(field)}"
    end
  end
end
