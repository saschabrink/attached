Application.ensure_all_started(:ecto_sql)

# Start the test repo
{:ok, _} = Attached.TestRepo.start_link()

# Run migrations
Ecto.Migrator.up(Attached.TestRepo, 0, Attached.TestMigrations, log: false)

# Start Oban in manual testing mode (jobs enqueued but not executed)
{:ok, _} = Oban.start_link(Application.fetch_env!(:attached, Oban))

{_disk, disk_config} =
  :attached
  |> Application.get_env(:storage_backends)
  |> Keyword.fetch!(:local)

Attached.Test.setup_storage!(root: disk_config[:root])

# S3 integration tests boot a local Garage server. They run as part of the
# normal suite whenever the binary is available (the dev shell provides it)
# and are excluded otherwise.
exclude = if System.find_executable("garage"), do: [], else: [:integration]
ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Attached.TestRepo, :manual)
