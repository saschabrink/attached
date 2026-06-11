defmodule Attached.Test do
  @moduledoc """
  Test helpers for `attached`.

  Use in `test/support/` only — these bypass the LiveView upload flow and
  assume you control the input file. Production code should go through
  changesets (`Attached.Ecto.Changeset.put_attached/3`).
  """

  alias Attached.Originals.Original

  @doc """
  Configures the storage backend registry to a single Disk instance named
  `:local` against a unique tmp directory and registers an `at_exit` cleanup.
  Returns the storage root.

  Replaces any `:storage_backends` config for the test run — ingested
  originals record `"local"` in their `storage_backend` column.

  Call once from `test_helper.exs`:

      Attached.Test.setup_storage!()
      ExUnit.start()

  One directory is shared across the whole test run — async tests don't
  need per-test isolation because original keys are already unique. The
  directory is removed when the BEAM exits cleanly; if a test crashes
  the runner, leftover dirs in `/tmp/attached-test-*` are safe to delete.

  ## Options

    * `:base_url` — public base URL for served files (default `"/attachments"`)
    * `:root` — override the generated tmp path (mainly useful when you
      want a stable, gitignored path like `test/tmp/storage`)
  """
  def setup_storage!(opts \\ []) do
    root =
      Keyword.get(opts, :root) ||
        Path.join(System.tmp_dir!(), "attached-test-#{System.unique_integer([:positive])}")

    base_url = Keyword.get(opts, :base_url, "/attachments")

    File.rm_rf!(root)
    File.mkdir_p!(root)

    Application.put_env(:attached, :storage_backends, local: {Attached.StorageBackends.Disk, root: root, base_url: base_url})

    System.at_exit(fn _ -> File.rm_rf!(root) end)

    root
  end

  @doc """
  Attaches `upload` to `record.field` and returns the updated record.

  `upload` accepts:

    * a file path (binary) — filename and content type are inferred via
      `Path.basename/1` and `MIME.from_path/1`
    * a `%Plug.Upload{}` or any map with `:path` (and optionally `:filename`,
      `:content_type`)
    * an existing `%Attached.Originals.Original{}` — re-attached without storage I/O

  The schema's resolved FK column is read from `__attached_config__/1`,
  so per-field `:foreign_key` overrides and the global
  `:default_foreign_key_suffix` config are both honored.

  ## Example

      user = insert(:user) |> Attached.Test.attach!(:avatar, "test/support/fixtures/red.png")
  """
  def attach!(record, field, upload) do
    schema = record.__struct__

    case schema.__attached_config__(field) do
      {^field, _opts} ->
        record
        |> Ecto.Changeset.change()
        |> Attached.Ecto.Changeset.put_attached(field, normalize(upload))
        |> Attached.Repo.current().update!()

      nil ->
        raise ArgumentError,
              "#{inspect(schema)} does not have an attached field #{inspect(field)}"
    end
  end

  defp normalize(%Original{} = original), do: original

  defp normalize(path) when is_binary(path) do
    %{
      path: path,
      filename: Path.basename(path),
      content_type: MIME.from_path(path)
    }
  end

  defp normalize(other), do: other
end
