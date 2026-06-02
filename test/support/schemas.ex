defmodule Attached.Test.User do
  use Ecto.Schema
  use Attached.Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field(:name, :string)

    attached(:avatar,
      variants: %{
        thumb: [resize_to_fill: {100, 100}],
        medium: [resize_to_limit: {400, 400}]
      }
    )

    timestamps(type: :utc_datetime)
  end

  def changeset(user \\ %__MODULE__{}, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, [:name])
    |> Ecto.Changeset.validate_required([:name])
  end

  @doc """
  Demonstrates the intended changeset flow — `put_attached/3` is imported
  into the schema via `use Attached.Ecto.Schema` and can be called without a
  module prefix.
  """
  def changeset_with_avatar(user \\ %__MODULE__{}, attrs) do
    user
    |> changeset(attrs)
    |> put_attached(:avatar, Map.get(attrs, "avatar") || Map.get(attrs, :avatar))
  end
end
