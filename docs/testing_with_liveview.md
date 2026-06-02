# Testing with Phoenix LiveView

Patterns for testing LiveViews that use `attached` for file uploads. Covers
the test-helper setup, the upload-flow assertion pattern, a fixture helper
for tests that don't care about the upload UI, and common pitfalls.

## Setup

### Isolated storage per test run

`Attached.Test.setup_storage!/1` configures the Disk backend against a
unique tmp directory and registers an `at_exit` cleanup. Call it once
from `test_helper.exs`:

```elixir
# test/test_helper.exs
Attached.Test.setup_storage!()

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)
```

One directory is shared across the whole `mix test` invocation —
parallel `async: true` tests don't need per-test isolation because blob
keys are already unique. The dir lives under `System.tmp_dir!()`, so
there's nothing to gitignore.

Pass `:root` to pin the path (useful if you'd rather have a stable,
project-local storage dir):

```elixir
Attached.Test.setup_storage!(root: "test/tmp/storage")
```

### Oban in testing mode

`Attached.Blobs.extract_metadata_later/1` enqueues an Oban job after every
upload. In tests you want jobs *enqueued but not executed* by default, so
they don't race with assertions:

```elixir
# config/test.exs
config :my_app, Oban, testing: :manual, repo: MyApp.Repo
```

Drain explicitly when a test wants metadata extracted:

```elixir
Oban.drain_queue(queue: :default)
```

## Testing the upload flow

`Phoenix.LiveViewTest` exposes `file_input/3` and `render_upload/3` for
driving live_file_input components. The pattern: render the LiveView,
build an upload, submit, then assert a `%Blob{}` exists on the owner.

```elixir
test "user can upload an avatar", %{conn: conn, user: user} do
  {:ok, lv, _html} = live(conn, ~p"/users/#{user}/edit")

  avatar =
    file_input(lv, "#user-form", :avatar, [
      %{
        last_modified: 1_594_171_879_000,
        name: "avatar.png",
        content: File.read!("test/support/fixtures/avatar.png"),
        type: "image/png"
      }
    ])

  assert render_upload(avatar, "avatar.png") =~ "100%"

  lv
  |> form("#user-form", user: %{name: "Updated"})
  |> render_submit()

  user = MyApp.Repo.get!(User, user.id) |> MyApp.Repo.preload(:avatar_attached_blob)

  assert user.avatar_attached_blob.filename == "avatar.png"
  assert user.avatar_attached_blob.content_type == "image/png"
end
```

Two things to know:

* `file_input/3` only registers the upload — `render_upload/3` is what
  triggers `consume_uploaded_entries` in your LiveView.
* The form's `phx-submit` handler is what calls into `attached`. If your
  LiveView consumes uploads in the submit handler (the recommended
  pattern), the blob won't exist until after `render_submit/2`.

## Fixture helper for non-upload tests

Most tests that touch attached records aren't testing *the upload itself*
— they're testing the page that *displays* an already-uploaded file.
Going through the full upload flow for those tests is slow and noisy.

`Attached.Test.attach!/3` bypasses the LiveView flow and attaches a file
directly. It honors the schema's resolved FK (per-field `:foreign_key`
or the global `:default_foreign_key_suffix` config):

```elixir
setup do
  user =
    user_fixture()
    |> Attached.Test.attach!(:avatar, "test/support/fixtures/avatar.png")

  {:ok, user: user}
end
```

It accepts a file path (filename and content type are inferred), an
upload-shaped map (`%{path:, filename:, content_type:}`), a `%Plug.Upload{}`,
or an existing `%Attached.Blobs.Blob{}` for re-attachment without storage I/O.

### With ExMachina

ExMachina factories can't return a record with an attachment in one step
because `Attached.Test.attach!/3` persists, while ExMachina's `build/1`
returns an unsaved struct and `insert/1` calls `Repo.insert/1`. Expose
the attachment step as a separate piping helper instead:

```elixir
# test/support/factory.ex
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  def user_factory do
    %MyApp.User{
      name: "Test User",
      email: sequence(:email, &"user-#{&1}@example.com")
    }
  end

  @doc """
  Attaches a fixture file to `record.field`. Pipe after `insert/1`:

      user = insert(:user) |> with_attachment(:avatar)
  """
  def with_attachment(record, field, path \\ default_fixture(field)) do
    Attached.Test.attach!(record, field, path)
  end

  defp default_fixture(:avatar), do: "test/support/fixtures/avatar.png"
  defp default_fixture(:cover_image), do: "test/support/fixtures/cover.jpg"
  defp default_fixture(:document), do: "test/support/fixtures/sample.pdf"
end
```

Usage:

```elixir
import MyApp.Factory

user = insert(:user)                                                # no attachment
user = insert(:user) |> with_attachment(:avatar)                    # default fixture
user = insert(:user) |> with_attachment(:avatar, "test/support/fixtures/red.png")
```

The helper isn't a factory — `Attached.Test.attach!/3` already persists,
so adding `insert(:user_with_avatar)` would either skip the attachment
or double-insert. Keeping it as a pipe-friendly post-insert step avoids
that ambiguity.

## Testing variant generation

Variants are generated lazily on first `Attached.Variants.process/3` call.
In tests, just call them — the Disk backend writes a real file, libvips
or ImageMagick produces a real variant, and you can assert on the result:

```elixir
test "preview variant is generated for an image", %{user: user} do
  user = MyApp.Repo.preload(user, :avatar_attached_blob)

  assert {:ok, url} = Attached.Variants.preview_url(user.avatar_attached_blob)
  assert url =~ "/storage/"
end
```

For variants that go through the rendered HTML, assert on the markup:

```elixir
{:ok, _lv, html} = live(conn, ~p"/users/#{user}")
assert html =~ "avatar-variant.webp"
```

Variants are cached as `Attached.Variants.Variant` rows in
`attached_variants`, so subsequent renders in the same test are cheap —
no re-encoding.

`Attached.url(record, field, :variant_name)` requires `:variants` to be
preloaded on the blob — it raises with a helpful message if you forget.
Use `Attached.with_attached/2` in your queries (it preloads the blob and
its variants together) or `Repo.preload(record, avatar_attached_blob: :variants)`
explicitly.

## Common pitfalls

**libvips / ImageMagick missing on CI.** If your tests use variants, the
CI image needs `libvips` or `imagemagick` installed. The transformer
registry skips unavailable transformers, so a missing binary doesn't
crash — it just silently produces no variant. Add an explicit
`available?/0` assertion in test setup to catch missing deps early:

```elixir
unless Attached.Processors.Transformers.Vix.available?() do
  raise "libvips not installed — variants will not be generated in tests"
end
```

**Oban jobs racing with assertions.** Default `testing: :manual` means
`extract_metadata_later/1` jobs sit in the queue. If a test asserts on
`blob.metadata`, drain the queue first with `Oban.drain_queue/1` — or run
the worker directly:

```elixir
Attached.Blobs.BlobExtractMetadataWorker.perform(%Oban.Job{args: %{"blob_id" => blob.id}})
```

**Stale storage between runs.** If you skip the `at_exit` cleanup and run
many test suites locally, `/tmp` fills up. The unique-per-run directory
pattern above prevents test-to-test interference; the `at_exit` callback
handles long-term cleanup. If a test crashes mid-run, the directory
sticks around — periodic `rm -rf /tmp/attached-test-*` is fine.

**Async tests + shared owner records.** `attached` blobs themselves are
isolated per test via the SQL Sandbox, but if two tests both upload to
the same singleton-style owner record (a `Site` row, say), you'll get
sandbox conflicts. Use `async: false` for tests that mutate shared
fixtures, or scope each test to its own owner.
