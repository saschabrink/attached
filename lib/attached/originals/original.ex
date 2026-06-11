defmodule Attached.Originals.Original do
  @moduledoc """
  Stores metadata about an uploaded file.

  The actual file content lives on the configured storage service,
  referenced by the original's unique `key`. The `owner_table` and
  `owner_field` columns track which schema and field own this original,
  enabling orphan cleanup without polymorphic associations.

  Cached derivations live in `Attached.Variants.Variant` and are reached
  via the `:variants` has_many.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "attached_originals" do
    # Original-specific.
    field(:key, :string)
    field(:filename, :string)
    field(:storage_backend, :string)

    # Cleanup tracking — not an association, just data.
    field(:owner_table, :string)
    field(:owner_field, :string)

    # Shared with Attached.Variants.Variant — keep this block in sync.
    field(:content_type, :string)
    field(:byte_size, :integer)
    field(:checksum, :string)
    field(:metadata, :map, default: %{})

    has_many(:variants, Attached.Variants.Variant, foreign_key: :original_id)

    timestamps()
  end

  @identifier_format ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/

  def changeset(original \\ %__MODULE__{}, attrs) do
    original
    |> cast(attrs, ~w(key filename content_type byte_size checksum metadata storage_backend owner_table owner_field)a)
    |> validate_required(~w(key filename content_type byte_size checksum storage_backend owner_table owner_field)a)
    |> validate_format(:owner_table, @identifier_format, message: "must be a plain SQL identifier")
    |> validate_format(:owner_field, @identifier_format, message: "must be a plain SQL identifier")
    |> unique_constraint(:key)
  end

  @doc """
  Returns `true` when `value` is a plain SQL identifier — letters, digits,
  and underscores, not starting with a digit.

  `owner_table` and `owner_field` end up in SQL *identifier* positions
  (`Attached.Originals.get_owner/1`, `Attached.Originals.Scopes.orphans/3`)
  where they cannot be bound as query parameters, so `changeset/2` restricts
  them to this shape at ingest time. Schema-qualified names (`"public.users"`)
  are deliberately rejected — the interpolation sites treat the value as a
  single identifier.
  """
  def valid_identifier?(value) when is_binary(value), do: value =~ @identifier_format
  def valid_identifier?(_), do: false

  @base36 ~c"0123456789abcdefghijklmnopqrstuvwxyz"

  def generate_key do
    :crypto.strong_rand_bytes(28)
    |> :binary.bin_to_list()
    |> Enum.map(&Enum.at(@base36, rem(&1, 36)))
    |> List.to_string()
  end

  def image?(%__MODULE__{content_type: "image/" <> _}), do: true
  def image?(_), do: false

  def video?(%__MODULE__{content_type: "video/" <> _}), do: true
  def video?(_), do: false

  def audio?(%__MODULE__{content_type: "audio/" <> _}), do: true
  def audio?(_), do: false
end
