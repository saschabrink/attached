defmodule Attached.StorageBackends.S3.Client do
  @moduledoc false

  # Signs every request with SigV4 (see Attached.StorageBackends.S3.Signature)
  # and executes it via Req. URL building and response interpretation stay in
  # Attached.StorageBackends.S3 — this module only signs and executes.
  #
  # `req` is an optional dep — apps not using the S3 backend never load it.

  @compile {:no_warn_undefined, [Req]}

  alias Attached.StorageBackends.S3.Config
  alias Attached.StorageBackends.S3.Signature

  def request(method, url, opts \\ []) do
    body = Keyword.get(opts, :body, "")
    headers = session_token_headers() ++ Keyword.get(opts, :headers, [])

    signed_headers =
      Signature.sign_headers(credentials(), :calendar.universal_time(), method_string(method), url, headers, body)

    [method: method, url: url, headers: signed_headers, body: body, decode_body: false]
    |> Keyword.merge(Config.req_options())
    |> Req.request()
  end

  def presigned_url(url, method, expires_in, headers \\ []) do
    Signature.presign_url(credentials(), :calendar.universal_time(), method_string(method), url, expires_in, headers)
  end

  defp credentials do
    %{
      access_key_id: Config.fetch!(:access_key_id),
      secret_access_key: Config.fetch!(:secret_access_key),
      region: Config.region(),
      session_token: Config.get(:session_token)
    }
  end

  defp session_token_headers do
    case Config.get(:session_token) do
      nil -> []
      token -> [{"x-amz-security-token", token}]
    end
  end

  defp method_string(method), do: method |> Atom.to_string() |> String.upcase()
end
