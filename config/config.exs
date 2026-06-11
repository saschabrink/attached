import Config

if config_env() == :test do
  config :logger, level: :warning

  # Single registry entry — also exercises the "only entry becomes the
  # default" resolution, no :default_storage_backend needed.
  config :attached,
    repo: Attached.TestRepo,
    storage_backends: [
      local: {Attached.StorageBackends.Disk, root: Path.join([System.tmp_dir!(), "attached_test_storage"]), base_url: "/attachments"}
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
