# Renaming fields and tables

`attached_originals` tracks every file's `owner_table` and `owner_field`. When
you rename an attached field or its owner table with Ecto, add the matching
`Attached.Ecto.Migration.rename` call in the same migration — otherwise orphan
detection silently breaks: the nightly `PurgeOrphansWorker` no longer finds a
live FK for those originals and purges files that are still in use.

## Renaming a field

`attached :avatar` → `attached :profile_picture`:

```elixir
def up do
  rename table(:users), :avatar_attached_original_id, to: :profile_picture_attached_original_id
  Attached.Ecto.Migration.rename table(:users), :avatar, to: :profile_picture
end

def down do
  rename table(:users), :profile_picture_attached_original_id, to: :avatar_attached_original_id
  Attached.Ecto.Migration.rename table(:users), :profile_picture, to: :avatar
end
```

Note the second call takes the *attachment name* (`:avatar`), not the FK
column name — it rewrites the `owner_field` values stored in
`attached_originals`.

## Renaming a table

`users` → `accounts`:

```elixir
def up do
  rename table(:users), to: table(:accounts)
  Attached.Ecto.Migration.rename table(:users), to: table(:accounts)
end

def down do
  rename table(:accounts), to: table(:users)
  Attached.Ecto.Migration.rename table(:accounts), to: table(:users)
end
```
