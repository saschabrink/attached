defmodule Attached.StorageBackends.S3 do
  @moduledoc """
  Stores files on Amazon S3 or any S3-compatible service (MinIO, Cloudflare R2,
  DigitalOcean Spaces, ...).

  HTTP goes through the optional `req` dependency — newly generated Phoenix
  apps already include it; add it otherwise:

      {:req, "~> 0.5"}

  Request signing (SigV4) is implemented in-house — no AWS SDK or signing
  library required.

  ## Configuration

      config :attached,
        storage_backend: Attached.StorageBackends.S3,
        s3: [
          bucket: "my-bucket",
          region: "eu-central-1",
          access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
          secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
        ]

  Optional keys:

    * `:endpoint` — base URL of an S3-compatible service, e.g.
      `"http://localhost:9000"` (MinIO) or
      `"https://<account>.r2.cloudflarestorage.com"` (R2). When set,
      path-style addressing is used (`<endpoint>/<bucket>/<key>`); without it,
      virtual-host style against AWS
      (`https://<bucket>.s3.<region>.amazonaws.com/<key>`).
    * `:session_token` — STS session token for temporary credentials.
    * `:url_expires_in` — presigned URL lifetime in seconds (default `300`).
    * `:response_content_type` — when `true` (the default), `url/2` looks up
      the original/variant content type in the database and bakes it into the
      presigned URL as `response-content-type`, so browsers receive the real
      MIME type instead of S3's stored default. Set `false` to skip the lookup
      (e.g. when no repo is configured).
    * `:req_options` — extra options merged into every `Req.request/1`
      (timeouts, instrumentation, `plug: {Req.Test, ...}` for tests).

  ## URLs

  `url/2` returns a presigned S3 GET URL — files are served directly from S3,
  `Attached.Web.Plug` is not involved. The lifetime defaults to
  `:url_expires_in` and can be overridden per call with `expires_in:`.

  Note: `Attached.url/2,3` passes keys through `Attached.Web.Signer.sign/1`
  before they reach this backend, so `url/2` first unwraps that token back to
  the raw storage key (verifying the HMAC when `secret_key_base` is
  configured) and then presigns. The Signer's own `:url_expires_in` plays no
  role for S3 — only the presign expiry does.

  ## Limitations

    * `upload/3` and `compose/2` buffer file contents in memory. Fine for
      typical attachment sizes; multipart upload for very large files is a
      candidate for a future version.
    * `compose/2` concatenates by download + re-upload. S3's server-side
      compose (multipart `UploadPartCopy`) requires 5 MB minimum part sizes
      and is not used.
  """

  @behaviour Attached.StorageBackends.Behaviour

  alias Attached.StorageBackends.S3.Client
  alias Attached.StorageBackends.S3.Config
  alias Attached.StorageBackends.S3.XML

  @impl true
  def upload(key, source_path, _opts \\ []) do
    put_object(key, File.read!(source_path))
  end

  @impl true
  def download(key) do
    case Client.request(:get, object_url(key)) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> error(other)
    end
  end

  @impl true
  def download_chunk(key, %Range{} = range) do
    headers = [{"range", "bytes=#{range.first}-#{range.last}"}]

    case Client.request(:get, object_url(key), headers: headers) do
      {:ok, %{status: status, body: body}} when status in [200, 206] -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> error(other)
    end
  end

  @impl true
  def compose(source_keys, destination_key) do
    source_keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, acc} ->
      case download(key) do
        {:ok, data} -> {:cont, {:ok, [acc, data]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, iodata} -> put_object(destination_key, IO.iodata_to_binary(iodata))
      error -> error
    end
  end

  @impl true
  def delete(key) do
    case Client.request(:delete, object_url(key)) do
      {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
      other -> error(other)
    end
  end

  @impl true
  def delete_prefixed(prefix) do
    with {:ok, keys} <- list_keys(prefix) do
      Enum.reduce_while(keys, :ok, fn key, :ok ->
        case delete(key) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  @impl true
  def exists?(key) do
    match?({:ok, %{status: 200}}, Client.request(:head, object_url(key)))
  end

  @impl true
  def url(token_or_key, opts \\ []) do
    key = resolve_key(token_or_key)
    expires_in = opts[:expires_in] || Config.get(:url_expires_in, 300)

    key
    |> object_url()
    |> append_response_content_type(key)
    |> Client.presigned_url(:get, expires_in)
  end

  @impl true
  def direct_upload_url(key, opts \\ []) do
    expires_in = opts[:expires_in] || Config.get(:url_expires_in, 300)
    headers = direct_upload_headers(opts)

    {:ok, %{url: Client.presigned_url(object_url(key), :put, expires_in, headers), headers: headers}}
  end

  # ===== Private =====

  # These headers are baked into the presigned PUT signature, so the client
  # must send them verbatim — S3 then enforces the declared content type,
  # checksum (Content-MD5 is verified against the body), and size.
  defp direct_upload_headers(opts) do
    [
      {"content-type", opts[:content_type]},
      {"content-md5", opts[:checksum]},
      {"content-length", opts[:byte_size] && Integer.to_string(opts[:byte_size])}
    ]
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
  end

  defp put_object(key, body) do
    case Client.request(:put, object_url(key), body: body) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      other -> error(other)
    end
  end

  # ListObjectsV2, following NextContinuationToken pagination.
  defp list_keys(prefix, continuation_token \\ nil, acc \\ []) do
    query =
      [{"list-type", "2"}, {"prefix", prefix}] ++
        if(continuation_token, do: [{"continuation-token", continuation_token}], else: [])

    url = Config.bucket_url() <> "/?" <> encode_query(query)

    case Client.request(:get, url) do
      {:ok, %{status: 200, body: xml}} ->
        acc = acc ++ XML.text_values(xml, "Key")

        case XML.text_value(xml, "NextContinuationToken") do
          nil -> {:ok, acc}
          token -> list_keys(prefix, token, acc)
        end

      other ->
        error(other)
    end
  end

  # `Attached.url/2,3` signs keys before handing them to the backend, so what
  # arrives here is usually a Signer token, not a raw key. Unwrap it; fall back
  # to treating the input as a raw key for direct calls. Without a configured
  # `secret_key_base` the Signer "token" is plain Base64url — a raw key can
  # accidentally decode too, so only accept the decoded form when it is
  # printable (real keys are base36 with an optional `_variants/` prefix).
  defp resolve_key(token_or_key) do
    case Attached.Web.Signer.verify(token_or_key) do
      {:ok, key} -> if String.valid?(key), do: key, else: token_or_key
      {:error, _} -> token_or_key
    end
  end

  defp append_response_content_type(url, key) do
    with true <- Config.get(:response_content_type, true),
         content_type when is_binary(content_type) <- content_type_for(key) do
      url <> "?" <> encode_query([{"response-content-type", content_type}])
    else
      _ -> url
    end
  end

  # Same resolution as Attached.Web.Plug: originals carry their key, variant
  # paths are parsed back to the variant row.
  defp content_type_for(key) do
    case Attached.Originals.get_by_key(key) do
      %{content_type: content_type} ->
        content_type

      nil ->
        case Attached.Variants.get_by_path(key) do
          %{content_type: content_type} -> content_type
          nil -> nil
        end
    end
  end

  # SigV4 canonical query encoding (%20 for spaces) — URI.encode_query/1 emits
  # form encoding (`+`), which would break the signature.
  defp encode_query(pairs) do
    Enum.map_join(pairs, "&", fn {k, v} ->
      URI.encode(k, &URI.char_unreserved?/1) <> "=" <> URI.encode(v, &URI.char_unreserved?/1)
    end)
  end

  defp object_url(key) do
    encoded = URI.encode(key, &(URI.char_unreserved?(&1) or &1 == ?/))
    Config.bucket_url() <> "/" <> encoded
  end

  defp error({:ok, %{status: status, body: body}}), do: {:error, {:http, status, body}}
  defp error({:error, reason}), do: {:error, reason}
end
