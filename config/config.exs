import Config

if config_env() == :test do
  config :logger, level: :warning

  config :attached,
    repo: Attached.TestRepo,
    storage_backend: Attached.StorageBackends.Disk,
    disk: [
      root: Path.join([System.tmp_dir!(), "attached_test_storage"]),
      base_url: "/attachments"
    ]

  config :attached, Attached.TestRepo,
    database: "test/support/test.db",
    pool: Ecto.Adapters.SQL.Sandbox

  config :attached, ecto_repos: [Attached.TestRepo]

  config :attached, Oban,
    repo: Attached.TestRepo,
    engine: Oban.Engines.Lite,
    testing: :manual,
    queues: false,
    plugins: false
end
