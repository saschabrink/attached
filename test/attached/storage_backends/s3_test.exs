defmodule Attached.StorageBackends.S3Test do
  use ExUnit.Case, async: true

  alias Attached.StorageBackends.S3

  @stub Attached.StorageBackends.S3

  defp stub(fun), do: Req.Test.stub(@stub, fun)

  describe "upload/3" do
    test "PUTs the file body to the bucket path and signs the request" do
      parent = self()

      stub(fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:request, conn.method, conn.request_path, body, conn.req_headers})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      tmp = Path.join(System.tmp_dir!(), "attached-s3-test-#{System.unique_integer([:positive])}")
      File.write!(tmp, "hello s3")
      on_exit(fn -> File.rm(tmp) end)

      assert :ok = S3.upload("abc123", tmp)

      assert_received {:request, "PUT", "/abc123", "hello s3", headers}
      assert {"authorization", "AWS4-HMAC-SHA256 " <> _} = List.keyfind(headers, "authorization", 0)
      assert List.keyfind(headers, "x-amz-date", 0)
    end

    test "returns an error tuple on non-2xx responses" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 403, "denied") end)

      tmp = Path.join(System.tmp_dir!(), "attached-s3-test-#{System.unique_integer([:positive])}")
      File.write!(tmp, "x")
      on_exit(fn -> File.rm(tmp) end)

      assert {:error, {:http, 403, "denied"}} = S3.upload("abc123", tmp)
    end
  end

  describe "download/1" do
    test "returns the object body" do
      stub(fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/some-key"
        Plug.Conn.send_resp(conn, 200, "object-bytes")
      end)

      assert {:ok, "object-bytes"} = S3.download("some-key")
    end

    test "maps 404 to :not_found" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert {:error, :not_found} = S3.download("missing")
    end
  end

  describe "download_chunk/2" do
    test "sends a Range header" do
      stub(fn conn ->
        assert Plug.Conn.get_req_header(conn, "range") == ["bytes=10-19"]
        Plug.Conn.send_resp(conn, 206, "0123456789")
      end)

      assert {:ok, "0123456789"} = S3.download_chunk("some-key", 10..19)
    end
  end

  describe "compose/2" do
    test "concatenates the sources into the destination" do
      parent = self()

      stub(fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/part-a"} ->
            Plug.Conn.send_resp(conn, 200, "AAA")

          {"GET", "/part-b"} ->
            Plug.Conn.send_resp(conn, 200, "BBB")

          {"PUT", "/combined"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            send(parent, {:composed, body})
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      assert :ok = S3.compose(["part-a", "part-b"], "combined")
      assert_received {:composed, "AAABBB"}
    end

    test "halts on a missing source" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert {:error, :not_found} = S3.compose(["gone"], "combined")
    end
  end

  describe "delete/1" do
    test "treats 204 and 404 as success" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 204, "") end)
      assert :ok = S3.delete("some-key")

      stub(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)
      assert :ok = S3.delete("already-gone")
    end
  end

  describe "delete_prefixed/1" do
    test "lists with pagination, then deletes every key" do
      parent = self()

      stub(fn conn ->
        case conn.method do
          "GET" ->
            conn = Plug.Conn.fetch_query_params(conn)
            assert conn.query_params["list-type"] == "2"
            assert conn.query_params["prefix"] == "_variants/parent"

            xml =
              case conn.query_params["continuation-token"] do
                nil ->
                  """
                  <ListBucketResult>
                    <IsTruncated>true</IsTruncated>
                    <Contents><Key>_variants/parent-thumb-aaaa</Key></Contents>
                    <Contents><Key>_variants/parent-medium-bbbb</Key></Contents>
                    <NextContinuationToken>tok&amp;1</NextContinuationToken>
                  </ListBucketResult>
                  """

                "tok&1" ->
                  """
                  <ListBucketResult>
                    <IsTruncated>false</IsTruncated>
                    <Contents><Key>_variants/parent-large-cccc</Key></Contents>
                  </ListBucketResult>
                  """
              end

            conn
            |> Plug.Conn.put_resp_content_type("application/xml")
            |> Plug.Conn.send_resp(200, xml)

          "DELETE" ->
            send(parent, {:deleted, conn.request_path})
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      assert :ok = S3.delete_prefixed("_variants/parent")

      assert_received {:deleted, "/_variants/parent-thumb-aaaa"}
      assert_received {:deleted, "/_variants/parent-medium-bbbb"}
      assert_received {:deleted, "/_variants/parent-large-cccc"}
    end
  end

  describe "exists?/1" do
    test "true on 200, false on 404" do
      stub(fn conn ->
        assert conn.method == "HEAD"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert S3.exists?("some-key")

      stub(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)
      refute S3.exists?("missing")
    end
  end

  describe "url/2" do
    test "presigns a virtual-host GET URL with the default expiry" do
      url = S3.url("abc123def")

      assert url =~ "https://test-bucket.s3.eu-central-1.amazonaws.com/abc123def?"
      assert url =~ "X-Amz-Signature="
      assert url =~ "X-Amz-Expires=300"
      assert url =~ "X-Amz-Credential=AKIATESTKEY"
    end

    test "honors expires_in" do
      assert S3.url("abc123def", expires_in: 60) =~ "X-Amz-Expires=60"
    end

    test "unwraps tokens produced by Attached.Web.Signer" do
      token = Attached.Web.Signer.sign("abc123def")
      refute token == "abc123def"

      assert S3.url(token) =~ "amazonaws.com/abc123def?"
    end

    test "passes raw variant keys through unchanged" do
      # "_variants/..." contains "/", which is not Base64url — Signer.verify
      # fails and the key is used as-is.
      assert S3.url("_variants/parent-thumb-aaaa") =~ "amazonaws.com/_variants/parent-thumb-aaaa?"
    end
  end

  describe "direct_upload_url/2" do
    test "presigns a PUT with the metadata headers signed" do
      checksum = Base.encode64(:crypto.hash(:md5, "body"))

      assert {:ok, %{url: url, headers: headers}} =
               S3.direct_upload_url("abc123def",
                 content_type: "image/png",
                 checksum: checksum,
                 byte_size: 4
               )

      assert {"content-type", "image/png"} in headers
      assert {"content-md5", checksum} in headers
      assert {"content-length", "4"} in headers

      assert url =~ "https://test-bucket.s3.eu-central-1.amazonaws.com/abc123def?"
      # Signed header set is sorted and includes the metadata headers ("%3B" = ";").
      assert url =~ "X-Amz-SignedHeaders=content-length%3Bcontent-md5%3Bcontent-type%3Bhost"
      assert url =~ "X-Amz-Signature="
    end

    test "omits headers for options not given" do
      assert {:ok, %{url: url, headers: []}} = S3.direct_upload_url("abc123def")
      assert url =~ "X-Amz-SignedHeaders=host"
    end

    test "is exposed through the facade" do
      assert {:ok, %{url: _, headers: _}} = Attached.StorageBackends.direct_upload_url("abc123def")
    end
  end

  describe "XML helper" do
    alias Attached.StorageBackends.S3.XML

    test "extracts and unescapes values" do
      xml = "<R><Key>a&amp;b</Key><Key>c&lt;d</Key></R>"
      assert XML.text_values(xml, "Key") == ["a&b", "c<d"]
      assert XML.text_value(xml, "Missing") == nil
    end
  end

  describe "path-style endpoints" do
    test "bucket precedes the key in the URL path" do
      original = Application.get_env(:attached, :s3)

      Application.put_env(:attached, :s3, Keyword.put(original, :endpoint, "http://localhost:9000/"))
      on_exit(fn -> Application.put_env(:attached, :s3, original) end)

      assert S3.url("abc123def") =~ "http://localhost:9000/test-bucket/abc123def?"
    end
  end
end
