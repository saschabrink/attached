defmodule Attached.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/saschabrink/attached"

  def project do
    [
      app: :attached,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "File attachments for Ecto schemas",
      package: package(),
      name: "Attached",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:oban, "~> 2.18"},
      {:plug, "~> 1.14"},
      {:vix, "~> 0.31", optional: true},
      {:bupe, "~> 0.6", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      # Test deps
      {:ecto_sqlite3, "~> 0.17", only: :test},
      {:jason, "~> 1.4", only: [:dev, :test]}
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp aliases do
    [
      precommit: [
        "compile --warning-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "test"
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Sascha Brink"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/attached/changelog.html"
      },
      files: ~w(lib docs mix.exs README.md CHANGELOG.md LICENSE usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/testing_with_liveview.md"
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
