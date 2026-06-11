defmodule Attached.StorageBackends.S3IntegrationTest do
  # Runs the S3 backend against a real S3 server (Garage) — the suite boots
  # its own instance on free ports, so no manual setup is needed beyond the
  # `garage` binary (provided by the dev shell).
  #
  # Part of the normal `mix test` run when the binary is on PATH, excluded
  # otherwise (see test_helper.exs).
  #
  # Garage rather than MinIO or RustFS: nixpkgs marks minio as insecure
  # (unpatched 2026 CVEs — two of them signature-verification bypasses, which
  # disqualifies it as an oracle for our SigV4 implementation), and rustfs
  # isn't packaged in nixpkgs yet.
  #
  # The backend instance config is built in setup_all and passed through the
  # test context — no global state, so the module can run async.
  use ExUnit.Case, async: true

  @moduletag :integration
  @moduletag timeout: 120_000

  alias Attached.StorageBackends.S3
  alias Attached.StorageBackends.S3.Client
  alias Attached.StorageBackends.S3.Config

  @bucket "attached-integration"

  setup_all do
    garage =
      System.find_executable("garage") ||
        raise "garage binary not found — run inside the dev shell (flake.nix provides it)"

    s3_port = free_port()
    rpc_port = free_port()
    admin_port = free_port()
    base_dir = Path.join(System.tmp_dir!(), "attached-garage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(base_dir)

    config_path = Path.join(base_dir, "garage.toml")

    File.write!(config_path, """
    metadata_dir = "#{base_dir}/meta"
    data_dir = "#{base_dir}/data"
    replication_factor = 1

    rpc_bind_addr = "127.0.0.1:#{rpc_port}"
    rpc_public_addr = "127.0.0.1:#{rpc_port}"
    rpc_secret = "#{Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)}"

    [s3_api]
    s3_region = "garage"
    api_bind_addr = "127.0.0.1:#{s3_port}"
    root_domain = ".s3.garage.localhost"

    [admin]
    api_bind_addr = "127.0.0.1:#{admin_port}"
    """)

    port =
      Port.open({:spawn_executable, garage}, [
        :binary,
        :exit_status,
        # Garage logs to stderr; route it into the (unread) port mailbox so it
        # doesn't pollute the test output.
        :stderr_to_stdout,
        args: ["-c", config_path, "server"]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)

    on_exit(fn ->
      System.cmd("kill", ["#{os_pid}"], stderr_to_stdout: true)
      File.rm_rf!(base_dir)
    end)

    endpoint = "http://127.0.0.1:#{s3_port}"
    await_ready(endpoint)

    # One-node layout, then bucket + access key — all via the garage CLI.
    status = garage!(garage, config_path, ["status"])

    [node_id | _] = Regex.run(~r/^([0-9a-f]{8,})/m, status, capture: :all_but_first)

    garage!(garage, config_path, ["layout", "assign", "-z", "z1", "-c", "1G", node_id])
    garage!(garage, config_path, ["layout", "apply", "--version", "1"])
    garage!(garage, config_path, ["bucket", "create", @bucket])

    key_output = garage!(garage, config_path, ["key", "create", "attached-it"])

    [access_key_id | _] =
      Regex.run(~r/Key ID:\s*(\S+)/i, key_output, capture: :all_but_first) ||
        raise "could not parse access key id from:\n#{key_output}"

    [secret_access_key | _] =
      Regex.run(~r/Secret key:\s*(\S+)/i, key_output, capture: :all_but_first) ||
        raise "could not parse secret key from:\n#{key_output}"

    garage!(garage, config_path, ["bucket", "allow", "--read", "--write", @bucket, "--key", "attached-it"])

    config = [
      bucket: @bucket,
      region: "garage",
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      endpoint: endpoint,
      response_content_type: false,
      req_options: [retry: false]
    ]

    {:ok, config: config}
  end

  test "full object lifecycle: upload, exists?, download, ranged download, delete", %{config: config} do
    key = "it/lifecycle"
    tmp = tmp_file!("integration bytes")

    assert :ok = S3.upload(config, key, tmp)
    assert S3.exists?(config, key)

    assert {:ok, "integration bytes"} = S3.download(config, key)
    assert {:ok, "gration"} = S3.download_chunk(config, key, 4..10)

    assert :ok = S3.delete(config, key)
    refute S3.exists?(config, key)
    assert {:error, :not_found} = S3.download(config, key)

    # Deleting a missing key stays :ok.
    assert :ok = S3.delete(config, key)
  end

  test "presigned URLs are accepted by a real S3 implementation", %{config: config} do
    key = "it/presigned"
    tmp = tmp_file!("presigned body")
    assert :ok = S3.upload(config, key, tmp)

    url = S3.url(config, key)

    assert {:ok, %{status: 200, body: "presigned body"}} =
             Req.get(url, retry: false, decode_body: false)

    # Tampering with the signature must be rejected.
    tampered = String.replace(url, ~r/X-Amz-Signature=..../, "X-Amz-Signature=0000")
    assert {:ok, %{status: 403}} = Req.get(tampered, retry: false, decode_body: false)
  end

  test "extra query params are covered by the presigned signature", %{config: config} do
    key = "it/presigned-content-type"
    tmp = tmp_file!("plain text")
    assert :ok = S3.upload(config, key, tmp)

    url =
      Client.presigned_url(
        config,
        Config.bucket_url(config) <> "/#{key}?response-content-type=text%2Fplain",
        :get,
        300
      )

    assert {:ok, %{status: 200} = response} = Req.get(url, retry: false, decode_body: false)
    assert response.headers["content-type"] == ["text/plain"]
  end

  test "direct upload: presigned PUT with signed metadata headers", %{config: config} do
    body = "direct upload body"
    checksum = Base.encode64(:crypto.hash(:md5, body))

    assert {:ok, %{url: url, headers: headers}} =
             S3.direct_upload_url(config, "it/direct",
               content_type: "text/plain",
               checksum: checksum,
               byte_size: byte_size(body)
             )

    assert {:ok, %{status: status}} = Req.put(url, headers: headers, body: body, retry: false)
    assert status in 200..299
    assert {:ok, ^body} = S3.download(config, "it/direct")

    # A body that doesn't match the signed Content-MD5 must be rejected.
    assert {:ok, %{status: tampered_status}} =
             Req.put(url, headers: headers, body: "tampered body!!!!!", retry: false)

    assert tampered_status in [400, 403]
    assert {:ok, ^body} = S3.download(config, "it/direct")
  end

  test "compose concatenates objects", %{config: config} do
    assert :ok = S3.upload(config, "it/compose-a", tmp_file!("AAA"))
    assert :ok = S3.upload(config, "it/compose-b", tmp_file!("BBB"))

    assert :ok = S3.compose(config, ["it/compose-a", "it/compose-b"], "it/composed")
    assert {:ok, "AAABBB"} = S3.download(config, "it/composed")
  end

  test "delete_prefixed removes exactly the keys under the prefix", %{config: config} do
    assert :ok = S3.upload(config, "_variants/it-parent-thumb-aaaa", tmp_file!("v1"))
    assert :ok = S3.upload(config, "_variants/it-parent-medium-bbbb", tmp_file!("v2"))
    assert :ok = S3.upload(config, "_variants/it-other-thumb-cccc", tmp_file!("keep"))

    assert :ok = S3.delete_prefixed(config, "_variants/it-parent")

    refute S3.exists?(config, "_variants/it-parent-thumb-aaaa")
    refute S3.exists?(config, "_variants/it-parent-medium-bbbb")
    assert S3.exists?(config, "_variants/it-other-thumb-cccc")
  end

  # ===== Helpers =====

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # Any HTTP response (even a 4xx error document) means the S3 API is listening.
  defp await_ready(endpoint, attempts \\ 100)

  defp await_ready(endpoint, 0) do
    raise "S3 server at #{endpoint} did not become ready"
  end

  defp await_ready(endpoint, attempts) do
    case Req.get(endpoint, retry: false) do
      {:ok, %{status: status}} when is_integer(status) ->
        :ok

      _ ->
        Process.sleep(100)
        await_ready(endpoint, attempts - 1)
    end
  end

  defp garage!(binary, config_path, args) do
    case System.cmd(binary, ["-c", config_path | args], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, code} -> raise "garage #{Enum.join(args, " ")} failed (#{code}):\n#{output}"
    end
  end

  defp tmp_file!(content) do
    path = Path.join(System.tmp_dir!(), "attached-s3-it-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
