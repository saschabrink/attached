defmodule Attached.Web.Plug do
  @moduledoc """
  Plug for serving files from disk storage — and receiving direct uploads.

  ## Setup

      # In your router:
      forward "/attachments", Attached.Web.Plug

  Routes:

    * `GET /originals/:token` — serves the file behind the signed token
      (originals and variants alike; variants carry a `_variants/` prefix in
      the decoded key).
    * `PUT /originals/:token` — accepts a direct upload for the key behind
      the token. Only tokens signed with the `"direct_upload"` purpose are
      accepted (see `Attached.StorageBackends.direct_upload_url/2`), so
      download URLs can never be replayed as uploads. When the client sends a
      `Content-MD5` header, the received bytes are verified against it — the
      same check S3 performs.

  ## Options

    * `:max_upload_size` — maximum accepted PUT body in bytes. Default:
      unlimited (the disk backend is meant for dev/test; set a limit when
      exposing direct uploads publicly).

  When no `secret_key_base` is configured tokens are unsigned (development
  convenience) — uploads are then unauthenticated, so configure a secret
  anywhere that matters.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, path_info: ["originals", token]} = conn, _opts)
      when method in ["GET", "HEAD"] do
    case Attached.Web.Signer.verify(token) do
      {:ok, key} -> serve(conn, key)
      {:error, _} -> send_resp(conn, 403, "Forbidden")
    end
  end

  def call(%Plug.Conn{method: "PUT", path_info: ["originals", token]} = conn, opts) do
    case Attached.Web.Signer.verify(token, purpose: "direct_upload") do
      {:ok, key} -> receive_upload(conn, key, opts)
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

  # Streams the request body to a tmp file, verifies the Content-MD5 header
  # when present, then moves the file into storage.
  defp receive_upload(conn, key, opts) do
    max_size = Keyword.get(opts, :max_upload_size)
    tmp = Path.join(System.tmp_dir!(), "attached-direct-upload-#{System.unique_integer([:positive])}")

    try do
      case write_body(conn, tmp, max_size) do
        {:ok, conn} ->
          if md5_mismatch?(conn, tmp) do
            send_resp(conn, 400, "Content-MD5 mismatch")
          else
            :ok = Attached.StorageBackends.upload(key, tmp)
            send_resp(conn, 204, "")
          end

        {:error, :too_large, conn} ->
          send_resp(conn, 413, "Payload too large")
      end
    after
      File.rm(tmp)
    end
  end

  defp write_body(conn, tmp, max_size) do
    File.open!(tmp, [:write, :binary], fn file -> stream_body(conn, file, max_size) end)
  end

  defp stream_body(conn, file, remaining) do
    case read_body(conn) do
      {:more, data, conn} ->
        case take(remaining, data) do
          :too_large ->
            {:error, :too_large, conn}

          remaining ->
            IO.binwrite(file, data)
            stream_body(conn, file, remaining)
        end

      {:ok, data, conn} ->
        case take(remaining, data) do
          :too_large ->
            {:error, :too_large, conn}

          _remaining ->
            IO.binwrite(file, data)
            {:ok, conn}
        end
    end
  end

  defp take(nil, _data), do: nil
  defp take(remaining, data) when byte_size(data) > remaining, do: :too_large
  defp take(remaining, data), do: remaining - byte_size(data)

  defp md5_mismatch?(conn, path) do
    case get_req_header(conn, "content-md5") do
      [expected] -> md5_base64(path) != expected
      _ -> false
    end
  end

  defp md5_base64(path) do
    File.stream!(path, 65_536)
    |> Enum.reduce(:crypto.hash_init(:md5), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode64()
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
