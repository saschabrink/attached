defmodule Attached.StorageBackends.S3.Config do
  @moduledoc false

  def fetch!(key) do
    get(key) ||
      raise ArgumentError, "missing S3 configuration — set config :attached, s3: [#{key}: ...]"
  end

  def get(key, default \\ nil) do
    :attached
    |> Application.get_env(:s3, [])
    |> Keyword.get(key, default)
  end

  def region, do: get(:region, "us-east-1")

  def req_options, do: get(:req_options, [])

  @doc """
  Base URL of the bucket, without a trailing slash.

  Virtual-host style for AWS, path-style when a custom `:endpoint` is
  configured (MinIO, R2, and most other S3-compatibles expect path-style).
  """
  def bucket_url do
    case get(:endpoint) do
      nil -> "https://#{fetch!(:bucket)}.s3.#{region()}.amazonaws.com"
      endpoint -> String.trim_trailing(endpoint, "/") <> "/" <> fetch!(:bucket)
    end
  end
end
