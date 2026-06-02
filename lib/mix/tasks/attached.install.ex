defmodule Mix.Tasks.Attached.Install do
  @shortdoc "Generates the Attached base migration (originals + variants tables)"
  @moduledoc """
  Generates an Ecto migration that creates the `attached_originals` and
  `attached_variants` tables.

      $ mix attached.install

  The migration is placed in your app's `priv/repo/migrations` directory.
  """

  use Mix.Task

  import Mix.Generator

  @impl true
  def run(_args) do
    app = Mix.Project.config()[:app]
    migrations_path = Path.join(["priv", "repo", "migrations"])

    File.mkdir_p!(migrations_path)

    timestamp = timestamp()
    filename = "#{timestamp}_create_attached_tables.exs"
    path = Path.join(migrations_path, filename)

    create_file(path, migration_template(app))
    Mix.shell().info("Migration created: #{path}")
    Mix.shell().info("Run `mix ecto.migrate` to apply.")
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: "#{i}"

  defp migration_template(app) do
    """
    defmodule #{app |> to_string() |> Macro.camelize()}.Repo.Migrations.CreateAttachedTables do
      use Ecto.Migration

      def up, do: Attached.Ecto.Migration.up()
      def down, do: Attached.Ecto.Migration.down()
    end
    """
  end
end
