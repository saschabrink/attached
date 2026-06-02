defmodule Attached.Web.Plug do
  @moduledoc """
  Plug for serving files from disk storage.

  ## Setup

      # In your router:
      forward "/attachments", Attached.Web.Plug

  Handles two URL patterns:

    * `/originals/:key` — serves the original file
    * `/variants/:original_key/:digest` — serves (or generates) a variant
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  # All files (originals and variants) are served under /originals/:token.
  # The token is a signed storage key — variants have a "variants/" prefix in
  # the decoded key. When no secret_key_base is configured the token is the
  # raw key, which makes development and tests work without any setup.
  @impl true
  def call(%Plug.Conn{path_info: ["originals", token]} = conn, _opts) do
    case Attached.Web.Signer.verify(token) do
      {:ok, key} -> serve(conn, key)
      {:error, _} -> send_resp(conn, 403, "Forbidden")
    end
  end

  def call(conn, _opts) do
    send_resp(conn, 404, "Not found")
  end

  defp serve(conn, key) do
    if Attached.StorageBackends.exists?(key) do
      {:ok, data} = Attached.StorageBackends.download(key)

      conn
      |> put_resp_content_type(content_type_for(key))
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_resp(200, data)
    else
      send_resp(conn, 404, "Not found")
    end
  end

  # Originals are looked up by their unique storage key; variants don't have
  # a key column — `Variants.get_by_path/1` parses the path back to a
  # `(original_id, name, digest_prefix)` triple and looks the variant up via the
  # composite index.
  defp content_type_for(key) do
    case Attached.Originals.get_by_key(key) do
      %{content_type: ct} ->
        ct

      nil ->
        case Attached.Variants.get_by_path(key) do
          %{content_type: ct} -> ct
          nil -> "application/octet-stream"
        end
    end
  end
end
