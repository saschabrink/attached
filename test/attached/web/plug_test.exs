defmodule Attached.Web.PlugTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Attached.TestRepo

  import Plug.Test

  alias Attached.TestRepo, as: Repo
  alias Attached.Test.User

  @secret "plug-test-secret-long-enough-for-hmac"
  @opts Attached.Web.Plug.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

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

  describe "unknown routes" do
    test "returns 404" do
      conn = get("/unknown/path")
      assert conn.status == 404
    end
  end
end
