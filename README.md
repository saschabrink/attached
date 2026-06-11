# Attached

[![Hex.pm](https://img.shields.io/hexpm/v/attached.svg)](https://hex.pm/packages/attached)
[![Hexdocs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/attached)

File attachments for Ecto schemas. Inspired by Rails' Active Storage, designed for Ecto.

Attached gives your Ecto schemas declarative file attachments with variant support, a pluggable storage backend, and cleanup tracking — without polymorphic associations.

## Quick start

```elixir
# mix.exs
{:attached, "~> 0.2"},
{:vix, "~> 0.31"}  # recommended for variants — auto-installs libvips (alternative: system ImageMagick)
```

```bash
mix attached.install && mix ecto.migrate    # creates the attached_* tables
```

```elixir
# config/config.exs
config :attached,
  repo: MyApp.Repo,
  storage_backends: [
    local: {Attached.StorageBackends.Disk, root: Path.join(["priv", "attachments"])}
  ]

# router.ex — serves files from the Disk backend
forward "/attachments", Attached.Web.Plug
```

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  use Attached.Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    attached :avatar, variants: %{thumb: [resize_to_fill: {100, 100}]}
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> put_attached(:avatar, attrs["avatar"])
  end
end
```

```bash
mix attached.gen.migration MyApp.Accounts.User avatar && mix ecto.migrate
```

```heex
<img src={Attached.url(@user, :avatar, :thumb)} />
```

That's the whole integration — a `%Plug.Upload{}` (or LiveView upload) in the
params flows through your regular `Repo.insert`/`Repo.update`. The rest of this
README covers each step in detail.

## See it in action

- **Demo app** — [attached_phoenix_demo](https://github.com/saschabrink/attached_phoenix_demo)
  is a small Phoenix LiveView app showcasing the library end to end: clone it,
  run it, read the code.
- **Dashboard** — [`attached_dashboard`](https://hex.pm/packages/attached_dashboard)
  is a companion LiveView dashboard for inspecting originals, variants, owners,
  configured processors, and orphans:

[![attached_dashboard — overview page](https://raw.githubusercontent.com/saschabrink/attached/main/docs/screenshots/dashboard_overview.png)](https://github.com/saschabrink/attached_dashboard)

## Design principles

- **No polymorphic associations.** `attached` adds a foreign key column to your schema table. Multi-file attachments are user-defined join schemas with real foreign keys — no hidden join table behind a macro.
- **Changeset-native.** Attachments flow through your regular changeset pipeline. Works on create (UUIDs are generated before insert) and update alike.
- **Pluggable storage.** Ships with `Disk` and `S3` services (S3 via the optional `req` dep — already in new Phoenix apps). Add your own by implementing the `Attached.StorageBackends.Behaviour` behaviour.
- **On-the-fly variants.** Define named variants on your schema. The first `url/3` call generates the transformation on demand and caches it. Only schema-defined variant names are accepted — no ad-hoc transforms.
- **Cleanup-aware.** Each original tracks its `owner_table` and `owner_field` so orphaned files can be found and purged without scanning every table.

Some decisions look wrong at first glance but are deliberate — before you "fix"
one, read [WHY_DIDNT_YOU.md](WHY_DIDNT_YOU.md).

## Setup

### 1. Create the tables

```bash
mix attached.install
```

This generates a migration that delegates to `Attached.Ecto.Migration`:

```elixir
defmodule MyApp.Repo.Migrations.CreateAttachedTables do
  use Ecto.Migration

  def up, do: Attached.Ecto.Migration.up()
  def down, do: Attached.Ecto.Migration.down()
end
```

Which creates two tables:

- `attached_originals` — original-file metadata (filename, content_type, size, checksum, owner tracking)
- `attached_variants` — cached derivations joined via `original_id`

### 2. Configure storage and repo

```elixir
# config/config.exs
config :attached,
  repo: MyApp.Repo,
  storage_backends: [
    local: {Attached.StorageBackends.Disk, root: Path.join(["priv", "attachments"])}
  ]
```

Backends are named instances in a registry. With a single entry it is the
default automatically; with several, pick one:

```elixir
config :attached,
  default_storage_backend: :s3_main,
  storage_backends: [
    local: {Attached.StorageBackends.Disk, root: "priv/attachments"},
    s3_main: {Attached.StorageBackends.S3, bucket: "my-bucket", ...}
  ]
```

<a id="repo-configuration"></a>
For dynamic repos (multi-tenant apps), pass a `{mod, fun}` tuple or a zero-arity function instead of a module:

```elixir
config :attached, :repo, {MyApp.Tenant, :current_repo}
# or
config :attached, :repo, &MyApp.Tenant.current_repo/0
```

### 3. Add the controller route (for serving files)

Only needed for the Disk backend — the S3 backend serves presigned URLs
directly from S3, no route required.

```elixir
# router.ex
forward "/attachments", Attached.Web.Plug
```

### 4. Add the formatter config

```elixir
# .formatter.exs
[
  import_deps: [:ecto, :ecto_sql, :attached],
  ...
]
```

This exports `attached/1,2` as `locals_without_parens` so the formatter treats it like a DSL macro.

### 5. Make sure Oban is running

Attached's background jobs — metadata extraction after every upload,
`purge_later/2`, the orphan worker — run through [Oban](https://hex.pm/packages/oban),
a hard dependency of this package. Jobs go into the `:default` queue, so no
Attached-specific queue config is needed — but your app must run Oban. If it
doesn't yet, follow the [Oban installation guide](https://hexdocs.pm/oban/installation.html).
For the test-environment setup (`testing: :manual`), see the
[testing guide](docs/testing_with_liveview.md).

## Usage

### Declaring attachments

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  use Attached.Ecto.Schema

  schema "users" do
    field :name, :string

    attached :avatar, variants: %{
      thumb: [resize_to_fill: {100, 100}],
      medium: [resize_to_limit: {400, 400}]
    }
  end
end
```

`attached :avatar` generates a `belongs_to :avatar_attached_original` association and expects an `avatar_attached_original_id` UUID FK column on the `users` table.

### Multi-file attachments

There is intentionally no `attached_many` macro. Real galleries need a `position`, `caption`, soft-delete flag, or similar column on the join — a hidden join table cannot accommodate that. Use a plain Ecto join schema with `has_many` on the parent.

### Migrations

The migration generator is a convenience helper — you can write the migration by hand if you prefer. Respects the global FK-naming config (`config :attached, default_foreign_key_suffix:`).

```bash
mix attached.gen.migration MyApp.Accounts.User avatar
```

Adds a column:

```elixir
alter table(:users) do
  add :avatar_attached_original_id, references(:attached_originals, type: :binary_id, on_delete: :restrict)
end
```

### Renaming fields and tables

`attached_originals` tracks every file's `owner_table` and `owner_field`. When you rename a field or table with Ecto, add the matching `Attached.Ecto.Migration.rename` call — otherwise orphan detection silently breaks. See the [renaming guide](docs/renaming_fields_and_tables.md) for the migration recipes.

### Attaching files

`use Attached.Ecto.Schema` imports `put_attached/3`, which you call alongside `cast/3` and `validate_*` inside your changeset:

```elixir
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
```

Then in the controller/context it's just `Repo.insert` / `Repo.update` — nothing Attached-specific leaks in:

```elixir
%User{} |> User.changeset(params) |> Repo.insert()
```

The original record is inserted and the file uploaded inside `prepare_changes/2`, so everything runs in the same transaction as the parent row. A failed parent rollback also rolls back the original row; the orphaned storage file is swept up by the orphan worker.

`put_attached/3` accepts:
- A `%Plug.Upload{}` struct
- A `%{path: path, filename: filename, content_type: ct}` map (e.g. from `Phoenix.LiveView.consume_uploaded_entries/3`)
- An `Attached.Originals.Original` struct (to re-attach an existing original)
- `nil` (no-op, leaves the existing attachment untouched)

### Uploads with Phoenix LiveView

With LiveView uploads, consume the entries in your submit handler and pass the
resulting map into the params. One catch: LiveView deletes the temp file as
soon as the `consume_uploaded_entries/3` callback returns, but `put_attached/3`
reads it later, inside the changeset's `prepare_changes/2` — so copy it out
first:

```elixir
def mount(_params, _session, socket) do
  {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1)}
end

def handle_event("save", %{"user" => params}, socket) do
  avatar =
    consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
      dest = Path.join(System.tmp_dir!(), entry.uuid <> Path.extname(entry.client_name))
      File.cp!(path, dest)
      {:ok, %{path: dest, filename: entry.client_name, content_type: entry.client_type}}
    end)
    |> List.first()

  case Accounts.update_user(socket.assigns.user, Map.put(params, "avatar", avatar)) do
    {:ok, _user} -> ...
    {:error, changeset} -> ...
  end
end
```

`avatar` is `nil` when nothing was uploaded — `put_attached/3` treats that as
a no-op, so the same handler works with and without a new file. See
[attached_phoenix_demo](https://github.com/saschabrink/attached_phoenix_demo)
for the complete flow (form, progress, cancel, remove-image) and the
[testing guide](docs/testing_with_liveview.md) for testing it.

### Ingesting files from other sources

Outside the changeset/upload flow, `Attached.Originals` exposes three entry points — all funnel into the same pipeline (store, stat, checksum, insert, enqueue analysis):

```elixir
# From a local file on disk
Attached.Originals.create_from_file!(
  "/tmp/report.pdf",
  owner_table: "articles",
  owner_field: "attachment_attached_original_id"
)

# From any Enumerable of binary chunks — the primitive
Attached.Originals.create_from_stream!(
  stream,
  filename: "generated.csv",
  content_type: "text/csv",
  owner_table: "articles",
  owner_field: "attachment_attached_original_id"
)
```

Need to ingest from an HTTP URL? Attached intentionally stays out of the HTTP-client business — use your preferred library and hand the response body to `create_from_stream!/2`:

```elixir
# With Req
resp = Req.get!("https://example.com/image.png")

Attached.Originals.create_from_stream!(
  [resp.body],
  filename: "image.png",
  content_type: resp.headers["content-type"] |> List.first(),
  owner_table: "articles",
  owner_field: "header_image_attached_original_id"
)

# With Finch, Tesla, :httpc — anything that gives you bytes
```

The stream primitive is the escape hatch for anything we don't cover directly: S3 copies, database blobs, manually constructed buffers.

### Querying

```elixir
user = Repo.get(User, id) |> Repo.preload(avatar_attached_original: :variants)

Attached.url(user, :avatar)              # URL to the original file
Attached.url(user, :avatar, :thumb)      # URL to the thumb variant
Attached.attached?(user, :avatar)        # true/false
```

`Attached.url/3` with a variant name requires `:variants` to be preloaded
on the original and raises if it isn't. Either preload explicitly as above or
use `Attached.with_attached/2` (see below), which does both in one step.

### Preloading (N+1 prevention)

```elixir
User
|> Attached.with_attached(:avatar)
|> Repo.all()
# => preloads :avatar_attached_original and its variant records
```

For a custom join schema, use normal Ecto preloads:

```elixir
Article
|> Repo.all()
|> Repo.preload(images: :original)
```

### Template helpers

```elixir
# In a Phoenix component or template
<img src={Attached.url(@user, :avatar, :thumb)} />
```

### Variants

Variants are defined on the schema. On the first `url/3` call for a given variant, the transformation runs on demand, the result is stored as its own variant, and subsequent calls return the cached URL.

```elixir
attached :avatar, variants: %{
  thumb: [resize_to_fill: {100, 100}],
  medium: [resize_to_limit: {400, 400}],
  grayscale: [resize_to_limit: {200, 200}, colourspace: :"b-w"]
}
```

Only variant names declared in the schema are accepted by `url/3`. Arbitrary transform parameters are not supported — this prevents unbounded variant proliferation from being used as a resource-exhaustion attack.

Transformations run through the first available image transformer:
[Vix](https://hex.pm/packages/vix) (libvips NIF, recommended — add `{:vix, "~> 0.31"}`
to your deps) or ImageMagick (no Elixir package needed, just the `imagemagick`
system package — the `magick`/`convert` binary is auto-detected). Both support
the same operations: `resize_to_fill`, `resize_to_limit`, `resize_to_fit`,
`resize_and_pad`, `crop`, `rotate`, and `watermark`.

### Purging

```elixir
# Synchronous: deletes original record, variant records, and files from storage
Attached.purge(user, :avatar)

# Async via Oban: enqueues a purge job (returns immediately)
Attached.purge_later(user, :avatar)
```

Attached resolves the repo from `config :attached, :repo, MyApp.Repo`. See the [repo configuration section](#repo-configuration) below for dynamic repos.

### Purging on record delete

Ecto has no ActiveRecord-style `before_destroy` callbacks. Attached exposes the primitives (`purge_later/2`, `purge/2`) and lets you compose the delete flow yourself — soft deletes, audit trails, custom cascades all fit naturally. Use [`attached_dashboard`](https://hex.pm/packages/attached_dashboard) to inspect leftovers and clean up after the fact.

```elixir
def delete_user(%User{} = user) do
  user = Repo.preload(user, [:avatar_attached_original, images: :original])

  Repo.transact(fn ->
    Attached.purge_later(user, :avatar)
    Enum.each(user.images, &Attached.Originals.purge_later(&1.original))
    Repo.delete(user)
  end)
end
```

`purge_later/2` enqueues an Oban job per original — cheap, transactional, safe to call before the record delete. If the transaction rolls back, so do the enqueued jobs (they're inserted via Oban, which participates in Ecto transactions).

The nightly `PurgeOrphans` worker acts as a safety net for any originals whose owner was deleted without an explicit purge call.

### Orphan cleanup

Originals track their origin via `owner_table` and `owner_field`. A periodic cleanup job finds originals whose owner no longer references them:

```elixir
# In your Oban config
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 3 * * *", Attached.Originals.PurgeOrphansWorker}
    ]}
  ]
```

## Storage services

### Disk (built-in)

Stores files on the local filesystem. Serves them via `Attached.Web.Plug`.

```elixir
config :attached,
  storage_backends: [
    local: {Attached.StorageBackends.Disk, root: Path.join(["priv", "attachments"])}
  ]
```

### S3 (built-in)

Stores files on Amazon S3 or any S3-compatible service (MinIO, Cloudflare R2,
DigitalOcean Spaces). `Attached.url/2,3` returns presigned S3 URLs — files are
served directly from S3, no plug needed. Request signing (SigV4) is built in.

The only dependency is `req`, which newly generated Phoenix apps already
include. Add it otherwise:

```elixir
{:req, "~> 0.5"}
```

```elixir
config :attached,
  storage_backends: [
    s3_main: {Attached.StorageBackends.S3,
      bucket: "my-bucket",
      region: "eu-central-1",
      access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")}
  ]
```

For S3-compatible services, set `:endpoint` (switches to path-style addressing):

```elixir
config :attached,
  storage_backends: [
    s3_main: {Attached.StorageBackends.S3,
      bucket: "my-bucket",
      endpoint: "http://localhost:9000",
      access_key_id: "minioadmin",
      secret_access_key: "minioadmin"}
  ]
```

See `Attached.StorageBackends.S3` for all options (`:session_token`,
`:url_expires_in`, `:response_content_type`, `:req_options`).

### Custom service

Implement the `Attached.StorageBackends.Behaviour` behaviour:

> **Note:** Only one backend instance is active at a time — the one resolved as the default (`:default_storage_backend`, or the only registry entry). Each original row stores the instance name in its `storage_backend` column for audit purposes, but uploads, downloads, and deletes currently dispatch through the app-wide default. Switching the default means losing access to originals written by the previous one. Per-row dispatch is on the roadmap.


Every callback receives the instance's config keyword (its registry entry)
as the first argument — backend modules hold no global state.

```elixir
defmodule MyApp.Storage.Custom do
  @behaviour Attached.StorageBackends.Behaviour

  @impl true
  def upload(config, key, source_path, opts \\ []), do: ...

  @impl true
  def download(config, key), do: ...

  @impl true
  def download_chunk(config, key, range), do: ...

  @impl true
  def compose(config, source_keys, destination_key), do: ...

  @impl true
  def delete(config, key), do: ...

  @impl true
  def delete_prefixed(config, prefix), do: ...

  @impl true
  def exists?(config, key), do: ...

  @impl true
  def url(config, key, opts \\ []), do: ...
end

# Register it like any built-in:
config :attached,
  storage_backends: [
    custom: {MyApp.Storage.Custom, any: "options", your: "backend needs"}
  ]
```

## How it works

### Data model

```
┌──────────────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│            users             │   │  attached_originals  │   │  attached_variants   │
├──────────────────────────────┤   ├──────────────────────┤   ├──────────────────────┤
│ id                           │   │ id                   │   │ id                   │
│ name                         │   │ key                  │   │ original_id          │
│ avatar_attached_original_id ─┼──>│ filename             │<──┤ name                 │
│                              │   │ checksum             │   │ transform_digest     │
└──────────────────────────────┘   │ content_type         │   │ content_type         │
                                   │ byte_size            │   │ byte_size            │
                                   │ metadata (json)      │   │ metadata (json)      │
                                   │ owner_table          │   └──────────────────────┘
                                   │ owner_field          │
                                   └──────────────────────┘
```

A variant has no `key` of its own — its storage path is derived from
`(parent.key, variant.name, variant.transform_digest)` via `Attached.Variants.path_for/2`.

### How the pipeline works

Every upload flows through the same three stages — metadata extraction, optional transformation, and optional preview generation.

**MetadataExtractor** runs once after upload, reads the file, and stores extracted metadata in `original.metadata`. It produces no output file.

**Transformer** takes `(input_content_type, output_content_type)` pairs — image transformers declare `image/* → image/*`, custom modules can declare e.g. `application/pdf → text/plain` or `audio/mpeg → audio/ogg`. Dispatch picks the first transformer accepting the original's MIME + the variant's declared `mime_type:`.

**Previewer** is a fallback preprocessor for image-targeted variants when no direct transformer exists: non-image input (video, PDF) → image/png, which an image transformer then processes.

```
Upload
  │
  ▼
Original created (key, filename, content_type, byte_size, checksum)
  │
  ├─► Workers.ExtractMetadata  (Oban job, runs async after upload)
  │       └─► MetadataExtractors.find_for(content_type)
  │               Image  → width, height              ┐
  │               Video  → width, height, duration    ├─ stored in original.metadata
  │               Audio  → duration, bit_rate         ┘
  │
  └─► url/3 call (synchronous, on first request for a variant)
          │
          └─► Attached.Variants.process/3
                  ├─ checks attached_variants cache (original_id + transform_digest)
                  ├─ downloads original if not cached
                  └─► Transformers.find_for(original.content_type, target_mime)
                          Vix / ImageMagick  → image/* → image/*   (resize, crop, rotate …)
                          custom modules     → e.g. audio/mp3 → audio/ogg,
                                                    application/pdf → text/plain
                          └─ uploads to path_for(original, name, transform_digest), inserts Variant row,
                             returns %Variant{}

                  Fallback for image targets: Previewer (video frame, PDF page) produces
                  an image that's then handed to an image transformer.

          VariantTransformWorker can be used to eagerly pre-warm a variant
          (Oban job; resolves the transform spec from the schema at perform time).
```

### Lifecycle

1. **Attach** — For `attached`, `put_attached/3` inside a changeset uses `prepare_changes/2` to create the original record, upload the file to storage, and set the FK inside the parent's insert/update transaction. For a custom join schema, persist the parent first, then upload via `Attached.Originals.create_from_upload!/2` (or `Attached.upload_original/2`) and insert join rows pointing at the returned original.
2. **Serve** — `Attached.url/2,3` returns a URL. For variants, the first `url/3` call generates the transformation on demand and returns the cached URL on all subsequent calls.
3. **Purge** — `Attached.purge/2` deletes the original record, variant records, and files from storage. `purge_later/2` does the same via Oban.
4. **Cleanup** — `Attached.Originals.PurgeOrphansWorker` finds originals where `owner_table`/`owner_field` no longer match any live FK, and purges them.

## Guides

- [Testing with Phoenix LiveView](docs/testing_with_liveview.md) — test-helper setup, upload-flow assertions, fixture helpers, common pitfalls
- [Renaming fields and tables](docs/renaming_fields_and_tables.md) — keeping `owner_table`/`owner_field` tracking intact across renames
- [WHY_DIDNT_YOU.md](WHY_DIDNT_YOU.md) — design decisions that look wrong at first glance but are deliberate

## Active Storage parity

- [x] Single-file attachment (`attached`)
- [x] Multi-file attachments — write your own join schema (no macro)
- [x] Local disk storage
- [x] Signed URLs with expiry
- [x] Image variants (resize, crop, rotate)
- [x] Image analysis (width, height)
- [x] Video analysis (dimensions, duration, aspect ratio)
- [x] Audio analysis (duration, bit rate)
- [x] Video previews (thumbnail from video frame)
- [x] PDF previews (thumbnail from first page)
- [x] Content-type detection from magic bytes
- [x] Orphan cleanup
- [x] S3 storage (built-in, optional `req` dep)
- [ ] Mirror service (multi-backend writes) — see Roadmap
- [ ] Direct upload (browser → cloud) — see Roadmap

## Roadmap

Planned future additions:

| Feature | Notes |
|---|---|
| Direct upload | Browser → cloud uploads. Storage layer is done: presigned PUT URLs (`Attached.StorageBackends.direct_upload_url/2`, S3 + Disk), purpose-bound upload tokens, orphan grace period. Missing: pending-original creation, signed attach tokens, LiveView `external:` upload helpers |
| Mirror backend | `Attached.StorageBackends.Mirror` — a registry entry referencing other instances by name (`primary: :s3_main, mirrors: [:local]`); writes go to all, reads to the primary. Useful for zero-downtime storage migrations |
| Telemetry | Built-in `:telemetry` events for upload, extract, purge, and transform — consumed by the dashboard and user dashboards alike |
| Per-row storage backend dispatch | `StorageBackends.download(original)`/`delete(original)` resolve the backend instance from the original's `storage_backend` column, so apps can migrate from Disk to S3 (or run a mirror) without losing access to existing files |

## License

MIT
