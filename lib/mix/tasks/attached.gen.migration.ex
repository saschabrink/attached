defmodule Mix.Tasks.Attached.Gen.Migration do
  @shortdoc "Generates a migration for an attachment field"
  @moduledoc """
  Generates an Ecto migration for an `attached` field on a schema.

      $ mix attached.gen.migration MyApp.Accounts.User avatar

  Adds an `avatar_attached_original_id` column to the schema's table
  (respects `config :attached, default_foreign_key_suffix: "_original_id"`).
  """

  use Mix.Task

  import Mix.Generator

  @impl true
  def run(args) do
    case args do
      [schema_module, field] ->
        generate(schema_module, field)

      _ ->
        Mix.shell().error("""
        Usage: mix attached.gen.migration Schema field

        Example:
          mix attached.gen.migration MyApp.Accounts.User avatar
        """)
    end
  end

  defp generate(schema_module, field) do
    migrations_path = Path.join(["priv", "repo", "migrations"])
    File.mkdir_p!(migrations_path)

    module_parts = String.split(schema_module, ".")
    schema_name = List.last(module_parts) |> Macro.underscore()
    table_name = schema_name <> "s"

    timestamp = timestamp()
    name = "add_#{field}_attached_original_to_#{table_name}"
    filename = "#{timestamp}_#{name}.exs"
    content = one_migration(schema_module, table_name, field, name)

    path = Path.join(migrations_path, filename)
    create_file(path, content)
    Mix.shell().info("Run `mix ecto.migrate` to apply.")
  end

  defp one_migration(schema_module, table_name, field, name) do
    app = Mix.Project.config()[:app]

    migration_module =
      "#{app |> to_string() |> Macro.camelize()}.Repo.Migrations.#{Macro.camelize(name)}"

    fk_suffix = Application.get_env(:attached, :default_foreign_key_suffix, "_attached_original_id")
    fk_col = "#{field}#{fk_suffix}"

    """
    defmodule #{migration_module} do
      use Ecto.Migration

      def change do
        # #{schema_module} — attached :#{field}
        alter table(:#{table_name}) do
          add :#{fk_col}, references(:attached_originals, type: :binary_id, on_delete: :restrict)
        end

        create index(:#{table_name}, [:#{fk_col}])
      end
    end
    """
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: "#{i}"
end
