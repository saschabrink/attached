defmodule Attached.Web.Signer do
  @moduledoc """
  Signs and verifies storage keys for secure URL generation.

  A signed token encodes the storage key, an expiry timestamp, and a purpose,
  protected by an HMAC-SHA256 computed over the configured `secret_key_base`.
  The Plug verifies the token before serving (or accepting) any file.

  The purpose binds a token to one operation: a `"get"` token (the default,
  used for serving) is rejected by the direct-upload PUT endpoint and vice
  versa, so a leaked download URL can never be used to overwrite a file.

  ## Configuration

      config :attached,
        secret_key_base: "your-64-byte-secret",
        url_expires_in: 300   # seconds, default 5 minutes

  When `secret_key_base` is not configured, `sign/2` only Base64url-encodes
  the key and `verify/2` decodes without signature, expiry, or purpose
  checks — suitable for development and tests only.

  ## Token format

      Base64url(key|expiry|purpose).Base64url(hmac)

  where `hmac = HMAC-SHA256(secret, "key|expiry|purpose")`.
  """

  @default_purpose "get"

  @doc """
  Signs `key` and returns a URL-safe token.

  Options:

    * `:expires_in` — lifetime in seconds; falls back to the configured
      `url_expires_in`, or 300 if neither is set.
    * `:purpose` — operation this token is valid for (default `"get"`).
      `verify/2` only accepts the token for the same purpose.

  When no `secret_key_base` is configured the key is Base64url-encoded
  without HMAC, expiry, or purpose.
  """
  def sign(key, opts \\ []) do
    case secret() do
      nil ->
        # No HMAC — just encode so the key is always a single URL-safe segment.
        Base.url_encode64(key, padding: false)

      secret ->
        expires_in = opts[:expires_in] || Application.get_env(:attached, :url_expires_in, 300)
        purpose = Keyword.get(opts, :purpose, @default_purpose)
        expiry = System.system_time(:second) + expires_in
        payload = "#{key}|#{expiry}|#{purpose}"
        mac = compute_mac(secret, payload)
        Base.url_encode64(payload, padding: false) <> "." <> mac
    end
  end

  @doc """
  Verifies a signed token and returns `{:ok, key}` or `{:error, reason}`.

  Accepts the same `:purpose` option as `sign/2` (default `"get"`) — a token
  signed for a different purpose fails verification.

  When no `secret_key_base` is configured the token is decoded from Base64url
  and returned without signature, expiry, or purpose verification.
  """
  def verify(token, opts \\ []) do
    case secret() do
      nil ->
        case Base.url_decode64(token, padding: false) do
          {:ok, key} -> {:ok, key}
          :error -> {:error, :invalid}
        end

      secret ->
        expected_purpose = Keyword.get(opts, :purpose, @default_purpose)

        with [encoded_payload, mac] <- String.split(token, ".", parts: 2),
             {:ok, payload} <- Base.url_decode64(encoded_payload, padding: false),
             {:ok, {key, expiry_str, purpose}} <- split_payload(payload),
             true <- purpose == expected_purpose,
             {expiry, ""} <- Integer.parse(expiry_str),
             true <- System.system_time(:second) <= expiry,
             expected <- compute_mac(secret, payload),
             true <- secure_compare(mac, expected) do
          {:ok, key}
        else
          false -> {:error, :expired_or_invalid}
          _ -> {:error, :invalid}
        end
    end
  end

  # Tokens from before purposes were introduced carry only "key|expiry" —
  # treat them as the default purpose.
  defp split_payload(payload) do
    case String.split(payload, "|") do
      [key, expiry_str] -> {:ok, {key, expiry_str, @default_purpose}}
      [key, expiry_str, purpose] -> {:ok, {key, expiry_str, purpose}}
      _ -> :error
    end
  end

  defp compute_mac(secret, payload) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.url_encode64(padding: false)
  end

  # Constant-time comparison to prevent timing attacks.
  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    :crypto.hash_equals(a, b)
  end

  defp secret do
    Application.get_env(:attached, :secret_key_base)
  end
end
