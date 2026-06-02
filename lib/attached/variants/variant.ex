defmodule Attached.Variants.Variant do
  @moduledoc """
  A cached derivation of an `Attached.Originals.Original`.

  Variants are produced on demand from a parent original and a named transform
  declared on the parent schema (e.g. `:thumb`, `:preview`). Each variant
  is identified by `(original_id, transform_digest)` — the digest captures
  the full transform configuration, so changing a variant definition
  produces a new digest and a new cached variant, leaving the old one as
  an orphan to be reaped.

  Variants have no `key` of their own. Their storage path derives from
  the parent original's key plus the variant's name and transform digest.

  See `Attached.Originals.Original` for the original-file schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "attached_variants" do
    # Variant-specific. Underlying FK column is `original_id`.
    belongs_to :original, Attached.Originals.Original
    field :name, :string
    field :transform_digest, :string

    # Shared with Attached.Originals.Original — keep this block in sync.
    field :content_type, :string
    field :byte_size, :integer
    field :checksum, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(variant \\ %__MODULE__{}, attrs) do
    variant
    |> cast(attrs, ~w(original_id name transform_digest content_type byte_size checksum metadata)a)
    |> validate_required(~w(original_id name transform_digest content_type byte_size checksum)a)
    |> validate_format(:name, ~r/^[a-z0-9_]+$/, message: "must match [a-z0-9_] — no hyphens (used as variant-key separator)")
    |> foreign_key_constraint(:original_id)
    |> unique_constraint([:original_id, :transform_digest])
  end
end
