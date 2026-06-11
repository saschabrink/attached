# Changelog

## [Unreleased]

### Changed — BREAKING

- Storage backends are now **named instances** in a registry, replacing the
  single global backend pick (`config :attached, :storage_backend, Module` +
  per-module config keys like `:disk`/`:s3`):

      # Before
      config :attached,
        storage_backend: Attached.StorageBackends.S3,
        s3: [bucket: "my-bucket", ...]

      # After
      config :attached,
        storage_backends: [
          s3_main: {Attached.StorageBackends.S3, bucket: "my-bucket", ...}
        ]

  The default instance is the only registry entry, or — with several
  entries — the one named by `config :attached, :default_storage_backend`.
  Old config keys (`:storage_backend`, `:service`, `:disk`, `:s3`) raise
  with migration instructions instead of silently falling back to Disk.
  This makes multiple instances of the same backend possible (e.g. two S3
  buckets) and is the groundwork for the planned mirror backend and per-row
  dispatch.
- `Attached.StorageBackends.Behaviour` callbacks take the instance's config
  keyword as their first argument (`upload(config, key, source_path, opts)`,
  `download(config, key)`, ...). Custom backends must be updated; backend
  modules no longer read global application config.
- The `storage_backend` column on `attached_originals` records the instance
  name (e.g. `"local"`, `"s3_main"`) instead of the module name
  (`"Attached.StorageBackends.Disk"`) — mirrors Active Storage's
  `service_name`. Existing rows are not migrated automatically; the column is
  informational only (no dispatch reads it yet).
- `Attached.Test.setup_storage!/1` now configures the registry with a single
  Disk instance named `:local`.

### Added

- `Attached.StorageBackends.S3` — storage backend for Amazon S3 and
  S3-compatible services (MinIO, Cloudflare R2, DigitalOcean Spaces) via the
  optional `req` dependency (already included in new Phoenix apps). SigV4
  signing is implemented in-house and verified against the official AWS test
  vectors — no AWS SDK needed. Presigned GET URLs
  (`Attached.Web.Plug` not involved), ListObjectsV2-based
  `delete_prefixed/1` with pagination, STS session tokens, and optional
  `response-content-type` on presigned URLs resolved from the original/variant
  row. Path-style addressing via the `:endpoint` option for S3-compatibles.
- S3 integration suite that boots a local Garage server and exercises the
  full backend — including acceptance of our presigned URLs by a real S3
  implementation. Runs as part of `mix test` whenever the `garage` binary is
  available (the dev shell provides it), excluded otherwise.
- Direct-upload groundwork: `Attached.StorageBackends.direct_upload_url/2`
  returns a URL (plus required headers) for uploading a key straight from the
  browser via HTTP PUT. S3 presigns the PUT with `content-md5`,
  `content-type`, and `content-length` pinned in the signature; Disk serves a
  purpose-bound token handled by a new `PUT /originals/:token` route in
  `Attached.Web.Plug` (with optional `:max_upload_size` and Content-MD5
  verification). `Attached.Web.Signer` tokens now carry a purpose, so
  download URLs can never be replayed as uploads.

### Changed

- Orphan purging (`PurgeOrphansWorker`, `purge_by_owner_group/2`) now skips
  orphans younger than `config :attached, :orphan_grace_period` (default 48
  hours, `0` disables), so originals created ahead of their attachment —
  e.g. direct uploads in flight — survive the sweep. `list_orphans/...` and
  `count_orphans/...` still report all current orphans regardless of age.

### Fixed

- `path_for/1` now has an explicit `nil` clause, resolving an Elixir 1.20 type
  warning when tests pass `nil` to verify the security guard.
- Logger level set to `:warning` in test env, suppressing debug query output.
- All DB-touching tests migrated from `ExUnit.Case` + manual sandbox checkout to
  `Attached.DataCase`, eliminating sandbox ownership races.
- `ImageMagick.metadata/1` now returns `%{}` early for nonexistent paths via
  `File.exists?/1`, avoiding a noisy `identify` stderr error in tests.
- ImageMagick metadata tests use a JPEG fixture with an embedded EXIF orientation
  tag, eliminating the `unknown image property` stderr warning.
- `VixTest` now uses `Code.ensure_loaded?(Vix)` instead of `Code.ensure_loaded?(Vix.Vips.Image)`
  to avoid NIF load failure at compile time causing tests to be incorrectly skipped.

## [0.1.1] - 2026-06-08

### Fixed

- `.formatter.exs` was missing from the published Hex package, preventing
  `import_deps: [:attached]` from working for consumers.

## [0.1.0] - 2026-04-24

Initial release.

### Added

- `attached` macro for Ecto schemas — generates a `belongs_to
  :{name}_attached_original` association and expects a
  `{name}_attached_original_id` UUID FK column. Configurable per field
  via `:foreign_key` or globally via
  `config :attached, :default_foreign_key_suffix:`.
- `put_attached/3` — attach files inside a changeset via
  `prepare_changes/2`, transactional with the parent insert/update.
  Accepts `%Plug.Upload{}`, any map with `:path` (e.g. from
  `Phoenix.LiveView.consume_uploaded_entries/3`), an existing `%Original{}`
  (re-attach without storage I/O), or `nil` (no-op).
- `Attached.url/2,3` — URL to the original file or a named variant. Variant
  URLs trigger lazy generation on first call and return the cached URL on all
  subsequent calls. Raises `ArgumentError` if `:variants` is not preloaded on
  the original.
- `Attached.attached?/2` — boolean attachment check.
- `Attached.with_attached/2` — preloads the original and its variants in one
  shot. Use this instead of manual `Repo.preload` to avoid a second round-trip
  per variant URL call.
- `Attached.upload_original/2` — standalone original upload outside the
  changeset flow (e.g. Trix inline image uploads before an article is saved).
- `Attached.purge/2` — synchronously deletes the original record, all variant
  records, and all associated storage files.
- `Attached.purge_later/2` — same as `purge/2` but via an Oban job. Enqueues
  inside the current transaction, so a rollback cancels the job too.
- `attached_originals` table — stores files with `key`, `filename`,
  `storage_backend`, `content_type`, `byte_size`, `checksum`, `owner_table`,
  `owner_field`, `metadata` (JSON).
- `attached_variants` table — cached derivations. Fields: `original_id` (FK,
  `on_delete: :delete_all`), `name`, `transform_digest`, `content_type`,
  `byte_size`, `checksum`, `metadata`. `UNIQUE(original_id, transform_digest)`.
- `Attached.Variants` context — `list/1`, `get/2`, `get!/2`, `count/1`,
  `paginate/1`, `process/3`, `purge!/1`, `delete_for!/1`, `get_for/2`,
  `path_for/2,3`, `get_by_path/1`, `previewable?/1`, `preview_url/1`,
  `transforms_for/3`, `transform_digest/1`.
- `Attached.Variants.path_for/2,3` — single source of truth for variant
  storage paths: `"_variants/#{parent.key}-#{name}-#{digest[0..3]}"`. Variants
  live under `_variants/` so originals and variants can be handled separately
  in listings, backups, and cleanup sweeps.
- `Attached.Variants.get_by_path/1` — reverse of `path_for`; used by the plug
  to resolve the content type of a variant URL.
- Variant `quality:` option (integer 1–100) — applied to the encoder at write
  time. Different quality values produce distinct cached variants since
  `quality:` is included in the transform digest.
- Variant `fn:` option — bypass the built-in transformer with a named function
  capture. The function receives `(input_path, transforms, output_path)` and
  must return `:ok` or `{:error, reason}`. Anonymous functions are not accepted
  (non-deterministic digests).
- `Attached.Processors.Transformers` registry — transformers declare `accept?/2`
  with `(input_content_type, output_content_type)` pairs. Built-in: `Vix` and
  `ImageMagick` (both `image/* → image/*`). Non-image transforms
  (e.g. `application/pdf → text/plain`) are a first-class extension point via
  `Attached.Processors.Transformers.Behaviour`.
- `Attached.Processors.ImagePreviewers` — fallback stage for image-targeted
  variants when no direct transformer accepts the MIME pair. Built-in
  previewers: PDF (pdftoppm / mutool), video (ffmpeg), EPUB
  (gnome-epub-thumbnailer).
- `Attached.Processors.MetadataExtractors` — async analysis after upload.
  `Attached.Originals.ExtractMetadataWorker` runs the first accepting extractor
  and merges results into `original.metadata`: `width`/`height` for images,
  `width`/`height`/`duration`/`aspect_ratio`/`angle`/`audio`/`video` for
  video, `duration`/`bit_rate` for audio.
- `Attached.Originals` context — `list/1`, `get/2`, `get!/2`, `get_by_key/2`,
  `count/1`, `paginate/1`, `create_from_upload!/2`, `create_from_file!/2`,
  `create_from_stream!/2`, `update_metadata!/2`, `purge!/1`, `purge_later/1`,
  `list_owner_groups/0`, `list_orphan_groups/0`, `list_orphans/4`,
  `count_orphans/0,2`, `purge_orphans_later/0`, `purge_by_owner_group/2`,
  `extract_metadata_later/1`, `get_owner/1`.
- `Attached.Originals.Stats` — aggregate queries for dashboards:
  `overview/0`, `by_content_type/0`, `by_owner_group/0`,
  `by_storage_backend/0`.
- `Attached.Originals.PurgeOrphansWorker` — finds originals whose
  `owner_table`/`owner_field` no longer reference a live FK row and purges
  them. Schedule via Oban cron:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Cron, crontab: [
          {"0 3 * * *", Attached.Originals.PurgeOrphansWorker}
        ]}]

- `Attached.Variants.VariantTransformWorker` — Oban worker for eager variant
  pre-warming. Args: `{original_id, record_module, field, variant}`. Resolves
  transforms from the schema at perform time, computes the digest itself — no
  transform serialization needed.
- `Attached.StorageBackends.Disk` — local filesystem backend. Serves files via
  `Attached.Web.Plug` (`forward "/storage", Attached.Web.Plug`).
- `Attached.StorageBackends.Behaviour` — implement to add custom backends.
- `mix attached.install` — generates the initial migration (both tables).
  Future schema changes ship as versioned migrations:
  `Attached.Ecto.Migration.up(version: N)`.
- `mix attached.gen.migration SchemaModule field` — generates a per-attachment
  FK migration. Respects `config :attached, :default_foreign_key_suffix:`.
- `Attached.Ecto.Migration.rename/2` — keeps `owner_table`/`owner_field` in
  sync when renaming fields or tables. Call it alongside Ecto's own `rename`
  in your migration, otherwise orphan detection silently breaks.
- `.formatter.exs` exports `attached: 1, 2` as `locals_without_parens` and
  imports `:ecto`/`:ecto_sql` formatter configs.
- `Attached.Test` — test helpers: `setup_storage!/1` (configures Disk backend
  against a tmp dir with `at_exit` cleanup) and `attach!/3` (bypasses the
  changeset flow for test fixtures).
