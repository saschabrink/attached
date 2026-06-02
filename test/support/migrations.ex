defmodule Attached.TestMigrations do
  use Ecto.Migration

  def change do
    Oban.Migration.up(version: 12)

    # The lib's own migrations — exercises the real codepath in tests.
    Attached.Ecto.Migration.up()

    # Test-only fixture: users schema for changeset/preload tests
    create table(:users, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)

      add(
        :avatar_attached_original_id,
        references(:attached_originals, type: :binary_id, on_delete: :restrict)
      )

      timestamps(type: :utc_datetime)
    end
  end
end
