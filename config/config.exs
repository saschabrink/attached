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

  # S3 backend tests run against a Req.Test plug stub — no real bucket.
  config :attached,
    s3: [
      bucket: "test-bucket",
      region: "eu-central-1",
      access_key_id: "AKIATESTKEY",
      secret_access_key: "test-secret",
      response_content_type: false,
      req_options: [plug: {Req.Test, Attached.StorageBackends.S3}, retry: false]
    ]

  config :attached, Oban,
    repo: Attached.TestRepo,
    engine: Oban.Engines.Lite,
    testing: :manual,
    queues: false,
    plugins: false
end
