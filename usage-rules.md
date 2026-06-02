# attached usage rules

Rules apply to `attached ~> 0.1` — **pre-1.0, API may change.**

File attachments for Ecto schemas. Active Storage-inspired, but no
polymorphic associations: `attached` adds a real FK column.
Multi-file attachments are user-defined join schemas, not a macro.

## Minimal pattern

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  use Attached.Ecto.Schema                 # adds the attached macro

  schema "users" do
    field :name, :string

    attached :avatar, variants: %{
      thumb:  [resize_to_fill: {100, 100}],
      medium: [resize_to_limit: {400, 400}]
    }
  end
end
```

Goes through the schema's own changeset, via the imported `put_attached/3`:

```elixir
# in MyApp.Accounts.User
def changeset(user, attrs) do
  user
  |> cast(attrs, [:name])
  |> put_attached(:avatar, attrs["avatar"])
end
```

Callers stay Attached-free:

```elixir
%User{} |> User.changeset(params) |> Repo.insert!()
```

## Multi-file attachments

There is intentionally no `attached_many` macro. Write a plain Ecto
join schema with a `belongs_to :original, Attached.Originals.Original`:

```elixir
defmodule MyApp.Blog.ArticleImages.ArticleImage do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "article_images" do
    belongs_to :article, MyApp.Blog.Articles.Article
    belongs_to :original, Attached.Originals.Original, type: :binary_id, foreign_key: :attached_original_id
    field :position, :integer
    timestamps()
  end
end
```

Persist the parent first, upload via `Attached.upload_original/2`, then
insert join rows yourself.

## Setup

1. Install migration — creates `attached_originals` and `attached_variants`:

   ```bash
   mix attached.install
   ```

2. Per-attachment migration (convenience helper — write by hand if you prefer):

   ```bash
   mix attached.gen.migration MyApp.Accounts.User avatar
   ```

   Respects `config :attached, default_foreign_key_suffix:`.

3. Configure the service:

   ```elixir
   config :attached,
     storage_backend: Attached.StorageBackends.Disk,
     disk: [root: Path.join(["priv", "attachments"])],
     repo: MyApp.Repo
   ```

4. Router (for serving files via the built-in plug):

   ```elixir
   forward "/attachments", Attached.Web.Plug
   ```

5. Formatter config:

   ```elixir
   # .formatter.exs
   [import_deps: [:ecto, :ecto_sql, :attached], ...]
   ```

   Exports `attached/1,2` as `locals_without_parens`.

## Core API

| Function | Purpose |
|---|---|
| `put_attached(changeset, field, upload)` | Attach on `attached`. Imported by `use Attached.Ecto.Schema`. Upload runs in `prepare_changes/2` — same transaction as the parent insert/update |
| `Attached.url(record, field)` | URL to original file |
| `Attached.url(record, field, variant)` | URL to named variant (lazy-generated on first hit) |
| `Attached.attached?(record, field)` | Boolean |
| `Attached.with_attached(query, field)` | Preload helper — prevents N+1 |
| `Attached.purge(record, field)` | Sync delete: original + variants + files |
| `Attached.purge_later(record, field)` | Enqueues Oban job to purge |
| `Attached.upload_original(upload, opts)` | Standalone original upload (for join-schema multi-file flow) |

To delete a record and purge attachments in one transaction, compose it yourself:

```elixir
user = Repo.preload(user, [:avatar_attached_original, images: :original])

Repo.transact(fn ->
  Attached.purge_later(user, :avatar)
  Enum.each(user.images, &Attached.Originals.purge_later(&1.original))
  Repo.delete(user)
end)
```

Accepted upload shapes for `put_attached`:
- `%Plug.Upload{}`
- `%{path: path, filename: _, content_type: _}` (e.g. from `consume_uploaded_entries/3`)
- `%Attached.Originals.Original{}` (re-attach an existing original)
- `nil` — no-op (leaves existing attachment)

## Variants

Defined on the schema, generated lazily on first URL hit, cached as
their own variant. Powered by [Vix](https://hex.pm/packages/vix) / libvips.

```elixir
attached :avatar, variants: %{
  thumb:     [resize_to_fill: {100, 100}],
  grayscale: [resize_to_limit: {200, 200}, colourspace: :"b-w"]
}
```

Available ops: `resize_to_fill`, `resize_to_limit`, `resize_to_fit`,
`resize_and_pad`, `crop`, `rotate`, `watermark`.

`watermark` composites an overlay image (logo, badge) onto the result.
Place it after a resize so the overlay lands on the final-size image:

```elixir
attached :photo, variants: %{
  large: [
    resize_to_limit: {2000, 1000},
    watermark: [path: "priv/static/images/logo.png",
                gravity: :south_east, margin: 24, opacity: 0.6, scale: 0.2]
  ]
}
```

Options: `:path` (required), `:gravity` (default `:south_east`; any of
`:north_west`/`:north`/`:north_east`/`:west`/`:center`/`:east`/`:south_west`/`:south`/`:south_east`),
`:margin` (px inset, default `0`; integer for uniform, or `{horizontal, vertical}`),
`:opacity` (`0.0`–`1.0`, default `1.0`),
`:scale` (overlay width as a fraction of the base width; omit for native size).

`:path` may be absolute or relative. A **relative** path is joined onto the
app dir at runtime (like `Plug.Static`'s atom `:from`), so a file under `priv`
resolves both in dev and in a release — not against the cwd. The app defaults to
the one owning the configured repo; override with `config :attached, :otp_app, :my_app`.

## Orphan cleanup

Originals store `owner_table` + `owner_field`. Schedule the sweeper via Oban
cron:

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"0 3 * * *", Attached.Originals.OriginalPurgeOrphansWorker}]}
  ]
```

## Preloading

**Always use `Attached.with_attached/2`** instead of manual preloads —
it also loads variant records in one go.

```elixir
User
|> Attached.with_attached(:avatar)
|> Repo.all()
```

For single-shot reads on an existing record:

```elixir
user = Repo.get(User, id) |> Repo.preload(:avatar_attached_original)
```

For a join schema, use plain Ecto preloads:

```elixir
Article |> Repo.all() |> Repo.preload(images: :original)
```

## Do

- **`put_attached/3` for `attached`** inside the schema's `changeset/2`.
- **For multi-file**, write a join schema and insert rows by hand after
  the parent exists.
- **Configure the repo globally** (`config :attached, :repo, MyApp.Repo`).
  For dynamic repos, pass `{Mod, :fun}` or a zero-arity function instead.
- **Use `with_attached/2` in list queries.** Manual `Repo.preload(:avatar_attached_original)`
  misses the variant records and causes a second roundtrip per variant URL.
- **Accept `%Plug.Upload{}` and the LiveView map shape.** Both flow through
  `put_attached/3` — don't pre-convert in your controller/LiveView.
- **Purge with `purge_later/2`** when deleting large files on the request
  path. Sync `purge/2` blocks the user-facing action on a storage round-trip.

## Don't

- **Don't preload with `Repo.preload(:avatar)`.** The association is
  `:avatar_attached_original` (add `_attached_original` suffix). `with_attached(:avatar)` is the
  intended API — the suffix is an implementation detail.
- **Don't polymorphic-associate originals manually.** The `owner_table` +
  `owner_field` columns are for orphan cleanup only, not for querying
  "all originals for record X".
- **Don't configure the service per-request.** It's a global module pick;
  swap via `config :attached, :storage_backend, ...`.
- **Don't expect `attached` to work on update if you used a non-UUID
  primary key.** Blob FKs are `:binary_id` — your owner tables must use
  UUIDs too.

## Pre-1.0 caveat

APIs on `Attached.StorageBackends.Behaviour` (custom storage backends) and the variant
transformation pipeline may change in minor versions before 1.0. If you
implement a custom service, pin to a specific minor (`~> 0.1.0`, not
`~> 0.1`) and read `CHANGELOG.md` before upgrading.

## Testing

In tests, use the disk service pointed at a tmp dir:

```elixir
# config/test.exs
config :attached,
  storage_backend: Attached.StorageBackends.Disk,
  disk: [root: Path.join([System.tmp_dir!(), "attached_test"])],
  repo: MyApp.Repo
```

Remember to clean it up in `setup` or a `on_exit` hook — the disk
service doesn't clear itself between tests.

## Configuration

| Key | Purpose |
|---|---|
| `config :attached, :storage_backend, Module` | Storage backend (built-in: `Attached.StorageBackends.Disk`) |
| `config :attached, :disk, [root: path]` | Disk-service root |
| `config :attached, :repo, MyApp.Repo` | Ecto repo (module, `{mod, fun}`, or 0-arity function for dynamic repos) |
