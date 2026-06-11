defmodule Attached.Web.PlugTest do
  use Attached.DataCase, async: false
  use Oban.Testing, repo: Attached.TestRepo

  import Plug.Test

  alias Attached.Test.User

  @secret "plug-test-secret-long-enough-for-hmac"
  @opts Attached.Web.Plug.init([])

  setup do
    tmp_path = Path.join(System.tmp_dir!(), "plug_test_#{System.unique_integer([:positive])}.txt")
    File.write!(tmp_path, "hello plug")
    on_exit(fn -> File.rm(tmp_path) end)

    {:ok, upload: %{path: tmp_path, filename: "test.txt", content_type: "text/plain"}}
  end

  defp get(path), do: conn(:get, path) |> Attached.Web.Plug.call(@opts)

  describe "GET /originals/:token (unsigned, no secret configured)" do
    test "serves an existing file", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      url = Attached.url(user, :avatar)
      path = URI.parse(url).path |> String.replace_prefix("/attachments", "")

      conn = get(path)
      assert conn.status == 200
      assert conn.resp_body == "hello plug"
    end

    test "returns 404 for an unknown key" do
      conn = get("/originals/nonexistent-key")
      assert conn.status == 404
    end

    test "returns 404 for a signed but non-existent key" do
      token = Attached.Web.Signer.sign("nonexistent-original-key")
      conn = get("/originals/#{token}")
      assert conn.status == 404
    end
  end

  describe "GET /originals/:token (signed, secret configured)" do
    setup do
      Application.put_env(:attached, :secret_key_base, @secret)
      on_exit(fn -> Application.delete_env(:attached, :secret_key_base) end)
      :ok
    end

    test "serves a file with a valid signed token", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      url = Attached.url(user, :avatar)
      path = URI.parse(url).path |> String.replace_prefix("/attachments", "")

      conn = get(path)
      assert conn.status == 200
      assert conn.resp_body == "hello plug"
    end

    test "returns 403 for an invalid token" do
      conn = get("/originals/notavalidtoken")
      assert conn.status == 403
    end

    test "returns 403 for a tampered token", %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      url = Attached.url(user, :avatar)
      path = URI.parse(url).path |> String.replace_prefix("/attachments", "")
      # flip a char in the path
      tampered = String.replace_suffix(path, String.last(path), "X")

      conn = get(tampered)
      assert conn.status == 403
    end

    test "returns 403 for an expired token" do
      original_key = "expiry_test_#{System.unique_integer([:positive])}"
      expired_token = Attached.Web.Signer.sign(original_key, expires_in: -1)
      conn = get("/originals/#{expired_token}")
      assert conn.status == 403
    end
  end

  describe "GET /originals/:token with Range header" do
    # The fixture body is "hello plug" — 10 bytes.
    setup %{upload: upload} do
      user =
        User.changeset(%User{}, %{name: "Test"})
        |> Attached.Ecto.Changeset.put_attached(:avatar, upload)
        |> Repo.insert!()
        |> Repo.preload(avatar_attached_original: :variants)

      url = Attached.url(user, :avatar)
      {:ok, path: URI.parse(url).path |> String.replace_prefix("/attachments", "")}
    end

    defp get_range(path, range) do
      conn(:get, path)
      |> Plug.Conn.put_req_header("range", range)
      |> Attached.Web.Plug.call(@opts)
    end

    test "full responses advertise accept-ranges", %{path: path} do
      conn = get(path)
      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "accept-ranges") == ["bytes"]
    end

    test "bytes=N-M returns 206 with the slice and Content-Range", %{path: path} do
      conn = get_range(path, "bytes=0-4")
      assert conn.status == 206
      assert conn.resp_body == "hello"
      assert Plug.Conn.get_resp_header(conn, "content-range") == ["bytes 0-4/10"]
    end

    test "bytes=N- returns the tail", %{path: path} do
      conn = get_range(path, "bytes=6-")
      assert conn.status == 206
      assert conn.resp_body == "plug"
      assert Plug.Conn.get_resp_header(conn, "content-range") == ["bytes 6-9/10"]
    end

    test "bytes=-N returns the last N bytes", %{path: path} do
      conn = get_range(path, "bytes=-4")
      assert conn.status == 206
      assert conn.resp_body == "plug"
      assert Plug.Conn.get_resp_header(conn, "content-range") == ["bytes 6-9/10"]
    end

    test "last byte position is clamped to the file size", %{path: path} do
      conn = get_range(path, "bytes=6-999")
      assert conn.status == 206
      assert conn.resp_body == "plug"
      assert Plug.Conn.get_resp_header(conn, "content-range") == ["bytes 6-9/10"]
    end

    test "a range beyond the file returns 416", %{path: path} do
      conn = get_range(path, "bytes=100-")
      assert conn.status == 416
      assert Plug.Conn.get_resp_header(conn, "content-range") == ["bytes */10"]
    end

    test "a malformed range is ignored and the full file served", %{path: path} do
      conn = get_range(path, "bytes=abc")
      assert conn.status == 200
      assert conn.resp_body == "hello plug"
    end

    test "multi-range requests are ignored and the full file served", %{path: path} do
      conn = get_range(path, "bytes=0-1,4-5")
      assert conn.status == 200
      assert conn.resp_body == "hello plug"
    end

    test "ranges work for keys without a DB row (e.g. fresh direct uploads)" do
      key = "rangeable-#{System.unique_integer([:positive])}"
      :ok = Attached.StorageBackends.upload(key, write_tmp!("0123456789"))

      conn = get_range("/originals/#{Attached.Web.Signer.sign(key)}", "bytes=2-5")
      assert conn.status == 206
      assert conn.resp_body == "2345"
      assert Plug.Conn.get_resp_header(conn, "content-range") == ["bytes 2-5/10"]
    end

    defp write_tmp!(content) do
      tmp = Path.join(System.tmp_dir!(), "plug_range_#{System.unique_integer([:positive])}")
      File.write!(tmp, content)
      on_exit(fn -> File.rm(tmp) end)
      tmp
    end
  end

  describe "unknown routes" do
    test "returns 404" do
      conn = get("/unknown/path")
      assert conn.status == 404
    end
  end

  describe "PUT /originals/:token (direct upload)" do
    defp direct_upload_path(key, opts \\ []) do
      {:ok, %{url: url}} = Attached.StorageBackends.direct_upload_url(key, opts)
      String.replace_prefix(url, "/attachments", "")
    end

    defp put_upload(path, body, headers \\ []) do
      Enum.reduce(headers, conn(:put, path, body), fn {name, value}, conn ->
        Plug.Conn.put_req_header(conn, name, value)
      end)
      |> Attached.Web.Plug.call(@opts)
    end

    test "stores the body under the key and returns 204" do
      key = "direct-#{System.unique_integer([:positive])}"
      conn = put_upload(direct_upload_path(key), "uploaded bytes")

      assert conn.status == 204
      assert {:ok, "uploaded bytes"} = Attached.StorageBackends.download(key)
    end

    test "verifies Content-MD5 when sent" do
      key = "direct-#{System.unique_integer([:positive])}"
      body = "checked bytes"
      checksum = Base.encode64(:crypto.hash(:md5, body))

      conn = put_upload(direct_upload_path(key), body, [{"content-md5", checksum}])
      assert conn.status == 204

      key2 = "direct-#{System.unique_integer([:positive])}"
      conn = put_upload(direct_upload_path(key2), "tampered bytes", [{"content-md5", checksum}])
      assert conn.status == 400
      refute Attached.StorageBackends.exists?(key2)
    end

    test "rejects bodies above max_upload_size" do
      key = "direct-#{System.unique_integer([:positive])}"
      opts = Attached.Web.Plug.init(max_upload_size: 5)

      conn =
        conn(:put, direct_upload_path(key), "more than five bytes")
        |> Attached.Web.Plug.call(opts)

      assert conn.status == 413
      refute Attached.StorageBackends.exists?(key)
    end

    test "with a secret, rejects GET-purpose tokens for PUT and vice versa" do
      Application.put_env(:attached, :secret_key_base, @secret)
      on_exit(fn -> Application.delete_env(:attached, :secret_key_base) end)

      key = "direct-#{System.unique_integer([:positive])}"

      # Download token replayed as upload → 403.
      get_token = Attached.Web.Signer.sign(key)
      conn = put_upload("/originals/#{get_token}", "overwrite attempt")
      assert conn.status == 403

      # Upload token used for download → 403.
      {:ok, %{url: url}} = Attached.StorageBackends.direct_upload_url(key)
      conn = get(String.replace_prefix(url, "/attachments", ""))
      assert conn.status == 403

      # The real upload token works for PUT.
      conn = put_upload(String.replace_prefix(url, "/attachments", ""), "legit body")
      assert conn.status == 204
      assert {:ok, "legit body"} = Attached.StorageBackends.download(key)
    end
  end
end
