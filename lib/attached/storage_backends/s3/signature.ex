defmodule Attached.StorageBackends.S3.Signature do
  @moduledoc false

  # In-house AWS Signature Version 4 — the two slices the S3 backend needs:
  # signed request headers and presigned query params.
  #
  # Hand-rolled instead of pulling in `aws_signature` on purpose: SigV4 is a
  # frozen spec (unchanged since 2014) of pure HMAC-SHA256 composition, and
  # implementing it here keeps `req` — which newly generated Phoenix apps
  # already include — the backend's only external dependency. Verified against
  # the official AWS SigV4 test vectors in signature_test.exs.

  @algorithm "AWS4-HMAC-SHA256"
  @service "s3"
  @unsigned_payload "UNSIGNED-PAYLOAD"

  @typep credentials :: %{
           access_key_id: String.t(),
           secret_access_key: String.t(),
           region: String.t(),
           session_token: String.t() | nil
         }

  @doc """
  Signs a request via the `authorization` header.

  Returns the complete header list to send: the given `headers` plus `host`,
  `x-amz-date`, `x-amz-content-sha256`, and `authorization`. Headers passed in
  (e.g. `range`, `x-amz-security-token`) are included in the signature.
  """
  @spec sign_headers(credentials, :calendar.datetime(), String.t(), String.t(), [{String.t(), String.t()}], binary()) ::
          [{String.t(), String.t()}]
  def sign_headers(creds, datetime, method, url, headers, body) do
    uri = URI.parse(url)
    payload_digest = hex(:crypto.hash(:sha256, body))

    headers = [
      {"host", host(uri)},
      {"x-amz-date", amz_datetime(datetime)},
      {"x-amz-content-sha256", payload_digest}
      | headers
    ]

    canonical_headers = canonicalize_headers(headers)
    signed_names = Enum.map_join(canonical_headers, ";", fn {name, _} -> name end)

    signature =
      [method, canonical_path(uri), canonical_query(query_pairs(uri)), header_block(canonical_headers), signed_names, payload_digest]
      |> Enum.join("\n")
      |> sign(creds, datetime)

    authorization =
      "#{@algorithm} Credential=#{creds.access_key_id}/#{scope(creds, datetime)}," <>
        "SignedHeaders=#{signed_names},Signature=#{signature}"

    [{"authorization", authorization} | headers]
  end

  @doc """
  Returns `url` with the SigV4 query parameters (`X-Amz-Algorithm`,
  `X-Amz-Credential`, ..., `X-Amz-Signature`) appended — a presigned URL,
  valid for `expires_in` seconds. Query params already present on `url`
  (e.g. `response-content-type`) are preserved and covered by the signature.
  """
  @spec presign_url(credentials, :calendar.datetime(), String.t(), String.t(), pos_integer()) :: String.t()
  def presign_url(creds, datetime, method, url, expires_in) do
    uri = URI.parse(url)

    auth_params =
      [
        {"X-Amz-Algorithm", @algorithm},
        {"X-Amz-Credential", "#{creds.access_key_id}/#{scope(creds, datetime)}"},
        {"X-Amz-Date", amz_datetime(datetime)},
        {"X-Amz-Expires", Integer.to_string(expires_in)},
        {"X-Amz-SignedHeaders", "host"}
      ] ++ session_token_params(creds)

    query = query_pairs(uri) ++ auth_params

    # Presigned URLs sign only the host header and an unsigned payload —
    # the body is unknown at signing time.
    signature =
      [method, canonical_path(uri), canonical_query(query), "host:#{host(uri)}\n", "host", @unsigned_payload]
      |> Enum.join("\n")
      |> sign(creds, datetime)

    "#{uri.scheme}://#{host(uri)}#{uri.path || "/"}?#{encode_query(query ++ [{"X-Amz-Signature", signature}])}"
  end

  # ===== Signing core =====

  # HMAC chain over the canonical request: derive the signing key from the
  # secret + scope components, then sign the string-to-sign.
  defp sign(canonical_request, creds, datetime) do
    string_to_sign =
      Enum.join(
        [@algorithm, amz_datetime(datetime), scope(creds, datetime), hex(:crypto.hash(:sha256, canonical_request))],
        "\n"
      )

    ("AWS4" <> creds.secret_access_key)
    |> hmac(amz_date(datetime))
    |> hmac(creds.region)
    |> hmac(@service)
    |> hmac("aws4_request")
    |> hmac(string_to_sign)
    |> hex()
  end

  defp scope(creds, datetime), do: "#{amz_date(datetime)}/#{creds.region}/#{@service}/aws4_request"

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  defp hex(binary), do: Base.encode16(binary, case: :lower)

  # ===== Canonicalization =====

  # Lowercase names, trim values and collapse inner whitespace runs, sort by
  # name, merge duplicate names with ",".
  defp canonicalize_headers(headers) do
    headers
    |> Enum.map(fn {name, value} ->
      {String.downcase(name), value |> to_string() |> String.trim() |> String.replace(~r/\s+/, " ")}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map(fn {name, values} -> {name, Enum.join(values, ",")} end)
  end

  defp header_block(canonical_headers) do
    Enum.map_join(canonical_headers, "", fn {name, value} -> "#{name}:#{value}\n" end)
  end

  # Each path segment percent-encoded (single-encode — S3, unlike other AWS
  # services, does not double-encode), "/" preserved.
  defp canonical_path(%URI{path: nil}), do: "/"
  defp canonical_path(%URI{path: path}), do: path |> String.split("/") |> Enum.map_join("/", &aws_encode/1)

  # Pairs sorted by encoded name (then value), "k=v" joined with "&".
  defp canonical_query(pairs) do
    pairs
    |> Enum.map(fn {key, value} -> {aws_encode(key), aws_encode(value)} end)
    |> Enum.sort()
    |> Enum.map_join("&", fn {key, value} -> key <> "=" <> value end)
  end

  defp query_pairs(%URI{query: nil}), do: []
  defp query_pairs(%URI{query: ""}), do: []

  defp query_pairs(%URI{query: query}) do
    query
    |> String.split("&")
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> {URI.decode(key), URI.decode(value)}
        [key] -> {URI.decode(key), ""}
      end
    end)
  end

  # Percent-encodes everything but unreserved characters, uppercase hex —
  # the encoding SigV4's canonical form requires.
  defp aws_encode(string), do: URI.encode(string, &URI.char_unreserved?/1)

  defp encode_query(pairs) do
    Enum.map_join(pairs, "&", fn {key, value} -> aws_encode(key) <> "=" <> aws_encode(value) end)
  end

  defp session_token_params(%{session_token: nil}), do: []
  defp session_token_params(%{session_token: token}), do: [{"X-Amz-Security-Token", token}]

  # ===== Datetime formatting =====

  defp amz_date({{year, month, day}, _time}) do
    :io_lib.format("~4..0B~2..0B~2..0B", [year, month, day]) |> IO.iodata_to_binary()
  end

  defp amz_datetime({_date, {hour, minute, second}} = datetime) do
    amz_date(datetime) <>
      (:io_lib.format("T~2..0B~2..0B~2..0BZ", [hour, minute, second]) |> IO.iodata_to_binary())
  end

  defp host(%URI{host: host, port: port, scheme: scheme}) do
    if port == URI.default_port(scheme), do: host, else: "#{host}:#{port}"
  end
end
