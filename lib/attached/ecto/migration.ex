defmodule Attached.Ecto.Migration do
  @moduledoc """
  Migrations create and modify the database tables Attached needs to function.

  ## Usage

  Generate a migration in your app:

      mix attached.install

  This creates a migration that delegates to `Attached.Ecto.Migration`:

      defmodule MyApp.Repo.Migrations.CreateAttachedTables do
        use Ecto.Migration

        def up, do: Attached.Ecto.Migration.up()
        def down, do: Attached.Ecto.Migration.down()
      end

  ## Upgrading

  When a new version of Attached requires schema changes, generate a new migration:

      mix ecto.gen.migration upgrade_attached_to_v2

  Then call `up` with the target version:

      def up, do: Attached.Ecto.Migration.up(version: 2)
      def down, do: Attached.Ecto.Migration.down(version: 2)
  """

  use Ecto.Migration

  @current_version 1

  @doc "Run all migrations up to the latest version, or a specific version."
  def up(opts \\ []) do
    version = Keyword.get(opts, :version, @current_version)
    Enum.each(1..version, &migrate_up/1)
  end

  @doc "Run all migrations down from the latest version, or a specific version."
  def down(opts \\ []) do
    version = Keyword.get(opts, :version, @current_version)
    Enum.each(version..1//-1, &migrate_down/1)
  end

  @doc """
  Updates `attached_originals` ownership tracking when a field or table is renamed.

  Mirrors Ecto's `rename/2,3` syntax — call it alongside the corresponding
  Ecto rename in your migration.

  ## Field rename

      def up do
        rename table(:users), :avatar_attached_original_id, to: :profile_picture_attached_original_id
        Attached.Ecto.Migration.rename table(:users), :avatar, to: :profile_picture
      end

      def down do
        rename table(:users), :profile_picture_attached_original_id, to: :avatar_attached_original_id
        Attached.Ecto.Migration.rename table(:users), :profile_picture, to: :avatar
      end

  ## Table rename

      def up do
        rename table(:users), to: table(:accounts)
        Attached.Ecto.Migration.rename table(:users), to: table(:accounts)
      end

      def down do
        rename table(:accounts), to: table(:users)
        Attached.Ecto.Migration.rename table(:accounts), to: table(:users)
      end
  """
  def rename(%Ecto.Migration.Table{name: owner_table}, old_field, to: new_field) do
    suffix = Application.get_env(:attached, :default_foreign_key_suffix, "_attached_original_id")
    old_col = "#{old_field}#{suffix}"
    new_col = "#{new_field}#{suffix}"

    execute(
      "UPDATE attached_originals SET owner_field = '#{new_col}' WHERE owner_table = '#{owner_table}' AND owner_field = '#{old_col}'",
      "UPDATE attached_originals SET owner_field = '#{old_col}' WHERE owner_table = '#{owner_table}' AND owner_field = '#{new_col}'"
    )
  end

  def rename(%Ecto.Migration.Table{name: old_table}, to: %Ecto.Migration.Table{name: new_table}) do
    execute(
      "UPDATE attached_originals SET owner_table = '#{new_table}' WHERE owner_table = '#{old_table}'",
      "UPDATE attached_originals SET owner_table = '#{old_table}' WHERE owner_table = '#{new_table}'"
    )
  end

  defp migrate_up(1) do
    create table(:attached_originals, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      # Original-specific.
      add(:key, :string, null: false)
      add(:filename, :string, null: false)
      add(:storage_backend, :string, null: false)
      add(:owner_table, :string, null: false)
      add(:owner_field, :string, null: false)

      # Shared with attached_variants — keep this block in sync.
      add(:content_type, :string, null: false)
      add(:byte_size, :bigint, null: false)
      add(:checksum, :string, null: false)
      add(:metadata, :map, default: %{}, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:attached_originals, [:key]))
    create(index(:attached_originals, [:owner_table, :owner_field]))

    create table(:attached_variants, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      # Variant-specific.
      add(:original_id, references(:attached_originals, type: :binary_id, on_delete: :delete_all), null: false)
      add(:name, :string, null: false)
      add(:transform_digest, :string, null: false)

      # Shared with attached_originals — keep this block in sync.
      add(:content_type, :string, null: false)
      add(:byte_size, :bigint, null: false)
      add(:checksum, :string, null: false)
      add(:metadata, :map, default: %{}, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:attached_variants, [:original_id, :transform_digest]))
    create(index(:attached_variants, [:original_id, :name]))
  end

  defp migrate_down(1) do
    drop(table(:attached_variants))
    drop(table(:attached_originals))
  end
end
