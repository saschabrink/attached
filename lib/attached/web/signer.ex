defmodule Attached.Web.Signer do
  @moduledoc """
  Signs and verifies storage keys for secure URL generation.

  A signed token encodes the storage key and an expiry timestamp, protected
  by an HMAC-SHA256 computed over the configured `secret_key_base`. The Plug
  verifies the token before serving any file.

  ## Configuration

      config :attached,
        secret_key_base: "your-64-byte-secret",
        url_expires_in: 300   # seconds, default 5 minutes

  When `secret_key_base` is not configured, `sign/1` returns the raw key
  and `verify/1` accepts any value — suitable for development and tests.

  ## Token format

      Base64url(key|expiry).Base64url(hmac)

  where `hmac = HMAC-SHA256(secret, "key|expiry")`.
  """

  @doc """
  Signs `key` and returns a URL-safe token.

  Accepts an optional `:expires_in` override (seconds). Falls back to the
  configured `url_expires_in`, or 300 seconds if neither is set.

  When no `secret_key_base` is configured the raw key is returned unchanged.
  """
  def sign(key, opts \\ []) do
    case secret() do
      nil ->
        # No HMAC — just encode so the key is always a single URL-safe segment.
        Base.url_encode64(key, padding: false)

      secret ->
        expires_in = opts[:expires_in] || Application.get_env(:attached, :url_expires_in, 300)
        expiry = System.system_time(:second) + expires_in
        payload = "#{key}|#{expiry}"
        mac = compute_mac(secret, payload)
        Base.url_encode64(payload, padding: false) <> "." <> mac
    end
  end

  @doc """
  Verifies a signed token and returns `{:ok, key}` or `{:error, reason}`.

  When no `secret_key_base` is configured the token is decoded from Base64url
  and returned without signature verification.
  """
  def verify(token) do
    case secret() do
      nil ->
        case Base.url_decode64(token, padding: false) do
          {:ok, key} -> {:ok, key}
          :error -> {:error, :invalid}
        end

      secret ->
        with [encoded_payload, mac] <- String.split(token, ".", parts: 2),
             {:ok, payload} <- Base.url_decode64(encoded_payload, padding: false),
             [key, expiry_str] <- String.split(payload, "|", parts: 2),
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
