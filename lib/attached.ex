defmodule Attached do
  @moduledoc """
  File attachments for Ecto schemas.

  ## Changeset integration

  Schemas that `use Attached.Ecto.Schema` automatically import `put_attached/3`
  for use inside their `changeset/2`:

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:name])
        |> put_attached(:avatar, attrs["avatar"])
      end

  See `Attached.Ecto.Changeset` for details.

  ## Querying

      Attached.url(user, :avatar)
      Attached.url(user, :avatar, :thumb)
      Attached.attached?(user, :avatar)

  ## Preloading

      User |> Attached.with_attached(:avatar) |> Repo.all()
  """

  require Ecto.Query

  # -------------------------------------------------------------------
  # Querying
  # -------------------------------------------------------------------

  @doc """
  Returns the URL for an attachment, optionally for a named variant.

      Attached.url(user, :avatar)
      Attached.url(user, :avatar, :thumb)

  Returns `nil` if no file is attached. Raises `ArgumentError` if `field` is
  not a declared `attached` field — a typo'd field name is a programming
  error, not an empty attachment.

  When called with a variant name, `:variants` must be preloaded on the
  original — either via `Attached.with_attached/2` (recommended) or
  `Repo.preload(record, avatar_attached_original: :variants)`. Raises `ArgumentError`
  otherwise.
  """
  def url(record, field, variant \\ nil)

  def url(record, field, nil) do
    case get_original(record, field) do
      nil -> nil
      original -> signed_url(original.key)
    end
  end

  def url(record, field, variant_name) do
    case get_original(record, field) do
      nil ->
        nil

      original ->
        transforms =
          record
          |> Attached.Variants.transforms_for(field, variant_name)
          |> Keyword.put(:variant_name, variant_name)

        transform_digest = Attached.Variants.transform_digest(transforms)

        variants =
          case original.variants do
            %Ecto.Association.NotLoaded{} ->
              raise ArgumentError,
                    "Attached.url/3 with a variant name requires :variants to be preloaded on the original. " <>
                      "Use `Attached.with_attached(query, #{inspect(field)})` or " <>
                      "`Repo.preload(record, #{inspect(:"#{field}_attached_original")}: :variants)`."

            list when is_list(list) ->
              list
          end

        variant =
          Enum.find(variants, &(&1.transform_digest == transform_digest)) ||
            Attached.Variants.process(original, transform_digest, transforms)

        signed_url(Attached.Variants.path_for(original, variant))
    end
  end

  @doc """
  Returns `true` if the record has a file attached for the given field.

  Raises `ArgumentError` if `field` is not a declared `attached` field.
  """
  def attached?(record, field) do
    {_, opts} = config_for!(record.__struct__, field)
    fk = Keyword.fetch!(opts, :foreign_key)
    not is_nil(Map.get(record, fk))
  end

  @doc """
  Returns an Ecto query with the attachment original preloaded.

      User |> Attached.with_attached(:avatar) |> Repo.all()
  """
  def with_attached(queryable, field) do
    Ecto.Query.preload(queryable, [{^:"#{field}_attached_original", :variants}])
  end

  # -------------------------------------------------------------------
  # Purging
  # -------------------------------------------------------------------

  @doc """
  Synchronously deletes the attachment: removes the original record,
  variant records, variant files, and all files from storage.

  Raises `ArgumentError` if `field` is not a declared `attached` field.
  """
  def purge(record, field) do
    case get_original(record, field) do
      nil ->
        :ok

      original ->
        fk = one_fk(record.__struct__, field)
        repo = Attached.Repo.current()

        record
        |> Ecto.Changeset.change(%{fk => nil})
        |> repo.update!()

        Attached.Originals.purge!(original)
    end
  end

  @doc """
  Enqueues an Oban job to purge the attachment asynchronously.

  Raises `ArgumentError` if `field` is not a declared `attached` field.
  """
  def purge_later(record, field) do
    case get_original(record, field) do
      nil -> {:ok, :noop}
      original -> Attached.Originals.purge_later(original)
    end
  end

  # -------------------------------------------------------------------
  # Standalone original upload
  # -------------------------------------------------------------------

  @doc """
  Creates an original and uploads the file to storage without a schema attachment context.

  Useful for endpoints that accept file uploads independently of a parent record
  (e.g. Trix inline image uploads before an article is saved).

  Options:
    * `:owner_table` (required) — the table name the original will eventually belong to
    * `:owner_field` (required) — the FK column name (e.g. `"attached_original_id"`)

  Returns the inserted `%Attached.Originals.Original{}`.
  """
  def upload_original(upload, opts) do
    Attached.Originals.create_from_upload!(upload, opts)
  end

  @doc """
  Returns a signed URL for a storage key.

  Useful when you have an original key and need a URL without going through
  `url/2` or `url/3` (which require a loaded schema record).

  Returns `{:ok, url}` on success, or `{:error, reason}` if the storage
  backend cannot produce a URL (misconfigured backend, missing
  credentials, signing failure, etc.).
  """
  def original_url(key) when is_binary(key) do
    {:ok, signed_url(key)}
  rescue
    e -> {:error, e}
  end

  # -------------------------------------------------------------------
  # Internals
  # -------------------------------------------------------------------

  defp get_original(record, field) do
    config_for!(record.__struct__, field)
    Map.get(record, :"#{field}_attached_original")
  end

  defp one_fk(schema, field) do
    {_, opts} = config_for!(schema, field)
    Keyword.fetch!(opts, :foreign_key)
  end

  # A typo'd field would otherwise read as "nothing attached" (nil URL,
  # no-op purge) — the kind of bug that hides in a template for an hour.
  defp config_for!(schema, field) do
    if function_exported?(schema, :__attached_config__, 1) do
      schema.__attached_config__(field) ||
        raise ArgumentError,
              "#{inspect(schema)} does not have an attached field #{inspect(field)} — " <>
                "declared: #{inspect(schema.__attached_fields__())}"
    else
      raise ArgumentError, "#{inspect(schema)} does not use Attached.Ecto.Schema"
    end
  end

  defp signed_url(key) do
    Attached.StorageBackends.url(Attached.Web.Signer.sign(key))
  end
end
