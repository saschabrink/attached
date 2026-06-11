defmodule Attached.StorageBackends.S3.Client do
  @moduledoc false

  # Signs every request with SigV4 (see Attached.StorageBackends.S3.Signature)
  # and executes it via Req. URL building and response interpretation stay in
  # Attached.StorageBackends.S3 — this module only signs and executes.
  #
  # `config` is the S3 backend instance's config keyword.
  #
  # `req` is an optional dep — apps not using the S3 backend never load it.

  @compile {:no_warn_undefined, [Req]}

  alias Attached.StorageBackends.S3.Config
  alias Attached.StorageBackends.S3.Signature

  def request(config, method, url, opts \\ []) do
    body = Keyword.get(opts, :body, "")
    headers = session_token_headers(config) ++ Keyword.get(opts, :headers, [])

    signed_headers =
      Signature.sign_headers(credentials(config), :calendar.universal_time(), method_string(method), url, headers, body)

    [method: method, url: url, headers: signed_headers, body: body, decode_body: false]
    |> Keyword.merge(Config.req_options(config))
    |> Req.request()
  end

  def presigned_url(config, url, method, expires_in, headers \\ []) do
    Signature.presign_url(credentials(config), :calendar.universal_time(), method_string(method), url, expires_in, headers)
  end

  defp credentials(config) do
    %{
      access_key_id: Config.fetch!(config, :access_key_id),
      secret_access_key: Config.fetch!(config, :secret_access_key),
      region: Config.region(config),
      session_token: Config.get(config, :session_token)
    }
  end

  defp session_token_headers(config) do
    case Config.get(config, :session_token) do
      nil -> []
      token -> [{"x-amz-security-token", token}]
    end
  end

  defp method_string(method), do: method |> Atom.to_string() |> String.upcase()
end
