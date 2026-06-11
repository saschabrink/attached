defmodule Attached.StorageBackends.S3.Config do
  @moduledoc false

  # Helpers over an S3 backend instance's config keyword — its entry in
  # `config :attached, :storage_backends`. No global lookups; the keyword is
  # threaded in from the facade.

  def fetch!(config, key) do
    Keyword.get(config, key) ||
      raise ArgumentError,
            "missing S3 configuration — add `#{key}: ...` to the backend's entry " <>
              "in `config :attached, :storage_backends`"
  end

  def get(config, key, default \\ nil), do: Keyword.get(config, key, default)

  def region(config), do: get(config, :region, "us-east-1")

  def req_options(config), do: get(config, :req_options, [])

  @doc """
  Base URL of the bucket, without a trailing slash.

  Virtual-host style for AWS, path-style when a custom `:endpoint` is
  configured (MinIO, R2, and most other S3-compatibles expect path-style).
  """
  def bucket_url(config) do
    case get(config, :endpoint) do
      nil -> "https://#{fetch!(config, :bucket)}.s3.#{region(config)}.amazonaws.com"
      endpoint -> String.trim_trailing(endpoint, "/") <> "/" <> fetch!(config, :bucket)
    end
  end
end
