defmodule Attached.Variants do
  @moduledoc """
  Context module for cached variant derivations of `Attached.Originals.Original`.

  A variant is produced on demand from a parent original and a named transform
  declared on the parent schema, then cached as an `Attached.Variants.Variant`
  row pointing back at its parent original via `original_id`.

  ## Custom transformations

  Use `fn:` to bypass the built-in transformer entirely:

      attached :report, variants: %{
        text: [fn: &__MODULE__.to_text/3, mime_type: "text/plain"]
      }

      def to_text(input_path, _transforms, output_path) do
        System.cmd("pdftotext", [input_path, output_path])
        :ok
      end

  The function receives `(input_path, transforms, output_path)` and must return
  `:ok` or `{:error, reason}`. Use named function captures only — anonymous
  functions produce non-deterministic variant digests.

  `mime_type:` sets the content type of the stored variant. Defaults to
  `"image/png"` when omitted.

  `quality:` (integer 1–100) sets the encoder quality for the output file.
  Honored by jpeg, webp, and gif; ignored for png. Different quality values
  produce distinct cached variants.

      attached :header_image, variants: %{
        medium: [resize_to_limit: {700, 700}, mime_type: "image/webp", quality: 80]
      }

  ## Querying

  This module exposes the standard CRUD shape against `attached_variants`:
  `list/1`, `get/2`, `get!/2`, `count/1`, `paginate/1`. See
  `Attached.Ecto.CRUD` for the supported option set.

      Attached.Variants.list(order_by: [desc: :inserted_at], limit: 50)
  """

  import Ecto.Query

  alias Attached.Originals.Original
  alias Attached.Ecto.CRUD
  alias Attached.Variants.Variant

  # ===== Variant CRUD =====

  @doc """
  Returns variants matching the given options.

  See `Attached.Ecto.CRUD` for the supported option set
  (`:preload`, `:order_by`, `:limit`, `:offset`, `:select`, `:distinct`,
  `:exclude_nil`, `:query`).
  """
  def list(opts \\ []), do: CRUD.list(Variant, opts)

  @doc """
  Fetches a variant by `id`. Returns `nil` if not found.

  Supports `:preload` and `:query`.
  """
  def get(id, opts \\ []), do: CRUD.get(Variant, id, opts)

  @doc """
  Fetches a variant by `id`. Raises `Ecto.NoResultsError` if not found.

  Supports `:preload` and `:query`.
  """
  def get!(id, opts \\ []), do: CRUD.get!(Variant, id, opts)

  @doc """
  Counts variants matching the given options.

  Accepts the same `:query` hook as `list/1`.
  """
  def count(opts \\ []), do: CRUD.count(Variant, opts)

  @doc """
  Paginates variants.

  Accepts the same `:query`/`:order_by`/`:preload`/`:select` options as
  `list/1`, plus:

    * `:page` — 1-based page number (default `1`)
    * `:per_page` — items per page (default `25`)

  Returns `%{entries: [...], total: n, page: p, per_page: pp}`.
  """
  def paginate(opts \\ []), do: CRUD.paginate(Variant, opts)

  # ===== Variant lifecycle =====

  @doc """
  Returns the cached `%Variant{}` for `original` with `transform_digest`,
  generating and storing it if it doesn't exist yet.

  Idempotent — safe to call concurrently; a unique index on
  `(original_id, transform_digest)` prevents duplicate rows.
  """
  def process(%Original{} = original, transform_digest, transforms) do
    Keyword.get(transforms, :variant_name) ||
      raise ArgumentError,
            "Attached.Variants.process/3 requires a :variant_name in transforms. " <>
              "Schema-declared variants set this automatically; pass it explicitly " <>
              "for ad-hoc calls."

    case get_for(original, transform_digest) do
      %Variant{} = variant -> variant
      nil -> generate(original, transform_digest, transforms)
    end
  end

  @doc """
  Deletes a variant and its storage file synchronously.

  Accepts a `%Variant{}` struct (with `:original` preloaded) or a variant id.
  """
  def purge!(variant_id) when is_binary(variant_id) do
    variant_id |> get!(preload: :original) |> purge!()
  end

  def purge!(%Variant{original: %Original{} = parent} = variant) do
    Attached.StorageBackends.delete(path_for(parent, variant))
    Attached.Repo.current().delete!(variant)
    :ok
  end

  @doc """
  Deletes all variants belonging to `original` — both their storage files and
  DB rows.

  Idempotent. Called explicitly from `Attached.Originals.purge!/1` before the
  parent delete so storage gets cleaned (FK cascade would handle the DB
  rows but not the files).
  """
  def delete_for!(%Original{} = original) do
    repo = Attached.Repo.current()
    variants = repo.all(from v in Variant, where: v.original_id == ^original.id)

    Enum.each(variants, fn variant ->
      Attached.StorageBackends.delete(path_for(original, variant))
    end)

    repo.delete_all(from v in Variant, where: v.original_id == ^original.id)
    :ok
  end

  @doc """
  Fetches the variant for `original` with `transform_digest`, or `nil` if none
  exists yet.
  """
  def get_for(%Original{} = original, transform_digest) when is_binary(transform_digest) do
    Attached.Repo.current().get_by(Variant, original_id: original.id, transform_digest: transform_digest)
  end

  @doc """
  Returns the storage path for `variant` (a `%Variant{}` or
  `{name, transform_digest}` pair) belonging to `parent`.

  Variants live under a `_variants/` namespace separate from the original
  files, so listings and backups can treat derived files independently.
  Prefix-based cleanup therefore requires two calls: one for the parent key
  and one for the `_variants/<parent.key>` prefix.
  """
  def path_for(%Original{} = parent, %Variant{name: name, transform_digest: transform_digest}) do
    path_for(parent, name, transform_digest)
  end

  def path_for(%Original{key: parent_key}, name, transform_digest)
      when is_binary(name) and is_binary(transform_digest) do
    "_variants/#{parent_key}-#{name}-#{binary_part(transform_digest, 0, 4)}"
  end

  @doc """
  Reverse of `path_for/2` — given a storage path, returns the matching
  variant (or `nil` if the path doesn't refer to one).

  Used by `Attached.Web.Plug` to resolve the variant's content type when
  serving a variant URL. Falls back to a `LIKE` match on the 4-char
  transform-digest prefix encoded in the path.
  """
  def get_by_path("_variants/" <> rest), do: get_by_path(rest)

  def get_by_path(path) when is_binary(path) do
    case String.split(path, "-", parts: 3) do
      [parent_key, name, digest_prefix] when byte_size(digest_prefix) == 4 ->
        case Attached.Originals.get_by_key(parent_key) do
          nil ->
            nil

          original ->
            Attached.Repo.current().one(
              from v in Variant,
                where:
                  v.original_id == ^original.id and v.name == ^name and
                    like(v.transform_digest, ^"#{digest_prefix}%"),
                limit: 1
            )
        end

      _ ->
        nil
    end
  end

  # ===== Preview API =====

  @preview_transforms [
    resize_to_limit: {400, 400},
    variant_name: :preview,
    mime_type: "image/png"
  ]

  @doc """
  Returns `true` when a preview image can be produced for `original`.

  Any `image/*` original is previewable. For other content types an image previewer
  must accept the type (which includes a runtime availability check — e.g.
  `ffmpeg` installed for video, `pdftoppm` for PDF).
  """
  def previewable?(%Original{content_type: "image/" <> _}), do: true

  def previewable?(%Original{content_type: ct}) when is_binary(ct) do
    not is_nil(Attached.Processors.ImagePreviewers.find_for(ct))
  end

  def previewable?(_), do: false

  @doc """
  Returns `{:ok, url}` for a cached preview image of `original`, generating
  the variant on first call. Returns `{:error, reason}` when the original is
  not previewable or the transform fails.

  The preview is a small `image/png` (≤400×400), cached as a variant so
  subsequent calls are cheap.
  """
  def preview_url(%Original{} = original) do
    if previewable?(original) do
      variant = process(original, transform_digest(@preview_transforms), @preview_transforms)
      Attached.original_url(path_for(original, variant))
    else
      {:error, :not_previewable}
    end
  rescue
    e -> {:error, e}
  end

  # ===== Helpers =====

  @doc """
  Returns the transforms configured for `variant_name` on `field` of `record`.

  Raises `ArgumentError` if the variant is not declared.
  """
  def transforms_for(record, field, variant_name) do
    variants = record.__struct__.__attached_variants__(field)

    case Map.fetch(variants, variant_name) do
      {:ok, transforms} ->
        transforms

      :error ->
        raise ArgumentError,
              "Unknown variant #{inspect(variant_name)} for field #{inspect(field)}"
    end
  end

  @doc """
  Returns the deterministic digest for `transforms`, used as the cache key
  in `attached_variants.transform_digest`.

  The `:variant_name` key is excluded from the hash so renaming a variant
  does not invalidate its cached original.
  """
  def transform_digest(transforms) do
    :crypto.hash(:sha256, :erlang.term_to_binary(Keyword.delete(transforms, :variant_name)))
    |> Base.encode16(case: :lower)
  end

  # ===== Private =====

  defp generate(%Original{} = original, transform_digest, transforms) do
    custom_fn = Keyword.get(transforms, :fn)
    mime_type = Keyword.get(transforms, :mime_type, "image/png")
    name = to_string(Keyword.fetch!(transforms, :variant_name))
    out_ext = ext_for(mime_type)

    {:ok, data} = Attached.StorageBackends.download(original.key)

    in_ext = original.filename |> Path.extname() |> String.downcase()
    tmp_input = Path.join(System.tmp_dir!(), "attached-#{original.id}-input#{in_ext}")
    tmp_preview = Path.join(System.tmp_dir!(), "attached-#{original.id}-preview.png")
    tmp_output = Path.join(System.tmp_dir!(), "attached-#{original.id}-output#{out_ext}")

    try do
      File.write!(tmp_input, data)

      result =
        if custom_fn do
          custom_fn.(tmp_input, transforms, tmp_output)
        else
          run_transform(original, mime_type, transforms, tmp_input, tmp_preview, tmp_output)
        end

      case result do
        :ok ->
          path = path_for(original, name, transform_digest)
          :ok = Attached.StorageBackends.upload(path, tmp_output)
          %{size: byte_size} = File.stat!(tmp_output)

          %{
            original_id: original.id,
            name: name,
            transform_digest: transform_digest,
            content_type: mime_type,
            byte_size: byte_size,
            checksum: compute_checksum(tmp_output)
          }
          |> Variant.changeset()
          |> Attached.Repo.current().insert!()

        {:error, reason} ->
          raise "Attached.Variants: transform failed — #{inspect(reason)}"
      end
    after
      File.rm(tmp_input)
      File.rm(tmp_preview)
      File.rm(tmp_output)
    end
  end

  # Dispatch pipeline:
  #
  #   1. Direct match — a transformer declares
  #      `accept?(original.content_type, target_mime)`. Run it on the original.
  #
  #   2. Image fallback — when the target is an image and an image previewer
  #      accepts the original's content type: image previewer produces an image/png,
  #      then an image-transformer accepting image/png → target runs.
  #
  #   3. Otherwise raise `Attached.Variants.NoTransformerError` — this is
  #      a configuration/install problem, not a runtime failure.
  defp run_transform(original, target_mime, transforms, tmp_input, tmp_preview, tmp_output) do
    direct = Attached.Processors.Transformers.find_for(original.content_type, target_mime)
    image_previewer = image_fallback_previewer(original.content_type, target_mime)
    fallback = image_previewer && Attached.Processors.Transformers.find_for("image/png", target_mime)

    cond do
      direct ->
        direct.transform(tmp_input, transforms, tmp_output)

      image_previewer && fallback ->
        with :ok <- image_previewer.preview(tmp_input, tmp_preview) do
          fallback.transform(tmp_preview, transforms, tmp_output)
        end

      true ->
        raise Attached.Variants.NoTransformerError,
          source: original.content_type,
          target: target_mime
    end
  end

  defp image_fallback_previewer(content_type, target_mime) do
    if String.starts_with?(target_mime, "image/"),
      do: Attached.Processors.ImagePreviewers.find_for(content_type)
  end

  # MD5 + base64, matching `Attached.Originals.compute_checksum/1` and the format
  # S3/GCS expect in `Content-MD5`. Used here to record the variant's checksum
  # in `attached_variants.checksum` for integrity checks against the stored
  # file (bit-rot, truncated transform output, etc). See WHY_DIDNT_YOU.md for
  # why MD5 is the right choice despite being cryptographically broken.
  defp compute_checksum(path) do
    File.stream!(path, 2_048)
    |> Enum.reduce(:crypto.hash_init(:md5), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode64()
  end

  defp ext_for("image/png"), do: ".png"
  defp ext_for("image/jpeg"), do: ".jpg"
  defp ext_for("image/webp"), do: ".webp"
  defp ext_for("image/gif"), do: ".gif"
  defp ext_for("text/plain"), do: ".txt"
  defp ext_for("text/html"), do: ".html"
  defp ext_for("text/markdown"), do: ".md"
  defp ext_for("application/pdf"), do: ".pdf"
  defp ext_for("application/json"), do: ".json"
  defp ext_for(_), do: ".bin"
end
