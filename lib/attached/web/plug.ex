defmodule Attached.Web.Plug do
  @moduledoc """
  Plug for serving files from disk storage — and receiving direct uploads.

  ## Setup

      # In your router:
      forward "/attachments", Attached.Web.Plug

  Routes:

    * `GET /originals/:token` — serves the file behind the signed token
      (originals and variants alike; variants carry a `_variants/` prefix in
      the decoded key). Files on the Disk backend are sent via sendfile —
      they are never buffered in memory. HTTP Range requests are answered
      with `206 Partial Content`, so browsers can seek in video/audio
      without downloading the whole file.
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
    meta = lookup_meta(key)

    case Attached.StorageBackends.path(key) do
      {:ok, path} ->
        serve_file(conn, path, meta)

      {:error, :not_supported} ->
        serve_blob(conn, key, meta)

      # The backend has local paths but rejected this key (blank, traversal
      # segments) — treat it like a missing file rather than crashing.
      {:error, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  # sendfile(2) path — zero-copy, the file never enters the BEAM heap. The
  # size for Content-Range comes from the filesystem, which is authoritative
  # over the DB row.
  defp serve_file(conn, path, meta) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} ->
        conn = put_serve_headers(conn, meta)

        case parse_range(conn, size) do
          nil ->
            send_file(conn, 200, path)

          {first, last} ->
            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
            |> send_file(206, path, first, last - first + 1)

          :unsatisfiable ->
            conn
            |> put_resp_header("content-range", "bytes */#{size}")
            |> send_resp(416, "")
        end

      {:error, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  # Fallback for backends without local paths: ranges go through
  # download_chunk/2 (memory bounded by the requested range), full responses
  # through download/1. Without a DB row the total size is unknown, so the
  # Range header is ignored (RFC 9110 permits that) and the file is served
  # whole.
  defp serve_blob(conn, key, meta) do
    conn = put_serve_headers(conn, meta)
    size = meta && meta.byte_size

    case size && parse_range(conn, size) do
      nil ->
        case Attached.StorageBackends.download(key) do
          {:ok, data} -> send_resp(conn, 200, data)
          {:error, _} -> send_resp(conn, 404, "Not found")
        end

      {first, last} ->
        case Attached.StorageBackends.download_chunk(key, first..last) do
          {:ok, data} ->
            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
            |> send_resp(206, data)

          {:error, _} ->
            send_resp(conn, 404, "Not found")
        end

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  defp put_serve_headers(conn, meta) do
    conn
    |> put_resp_content_type((meta && meta.content_type) || "application/octet-stream")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    # Without this header browsers don't attempt Range requests (no seeking).
    |> put_resp_header("accept-ranges", "bytes")
  end

  # Single byte range from the Range header, validated against `size`.
  # Returns `{first, last}` (inclusive) for 206, `:unsatisfiable` for 416, or
  # `nil` to ignore the header and serve the full file. Multi-range requests
  # are ignored — RFC 9110 permits that, and browsers request single ranges
  # for media seeking; multipart/byteranges responses aren't worth the
  # complexity.
  defp parse_range(conn, size) do
    case get_req_header(conn, "range") do
      ["bytes=" <> spec] ->
        if String.contains?(spec, ","), do: nil, else: parse_range_spec(spec, size)

      _ ->
        nil
    end
  end

  defp parse_range_spec(spec, size) do
    case String.split(spec, "-", parts: 2) do
      # bytes=-N — the last N bytes.
      ["", suffix] ->
        case parse_int(suffix) do
          n when is_integer(n) and n > 0 and size > 0 -> {max(size - n, 0), size - 1}
          n when is_integer(n) -> :unsatisfiable
          nil -> nil
        end

      # bytes=N- — from N to the end.
      [first, ""] ->
        case parse_int(first) do
          n when is_integer(n) and n < size -> {n, size - 1}
          n when is_integer(n) -> :unsatisfiable
          nil -> nil
        end

      # bytes=N-M.
      [first, last] ->
        with f when is_integer(f) <- parse_int(first),
             l when is_integer(l) <- parse_int(last) do
          cond do
            f > l -> nil
            f >= size -> :unsatisfiable
            true -> {f, min(l, size - 1)}
          end
        end

      # No "-" in the spec at all, e.g. "bytes=abc".
      _ ->
        nil
    end
  end

  defp parse_int(string) do
    case Integer.parse(string) do
      {n, ""} when n >= 0 -> n
      _ -> nil
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
  # composite index. The row provides the content type and the total size for
  # Content-Range; `nil` (no row) falls back to octet-stream without ranges.
  defp lookup_meta(key) do
    Attached.Originals.get_by_key(key) || Attached.Variants.get_by_path(key)
  end
end
