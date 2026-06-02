defmodule Attached.Web.SignerTest do
  use ExUnit.Case, async: true

  @secret "test-secret-at-least-32-bytes-long-for-hmac"

  setup do
    Application.put_env(:attached, :secret_key_base, @secret)
    on_exit(fn -> Application.delete_env(:attached, :secret_key_base) end)
    :ok
  end

  describe "sign/1" do
    test "returns a dot-separated Base64url token" do
      token = Attached.Web.Signer.sign("abc123")
      assert String.contains?(token, ".")
      [payload, mac] = String.split(token, ".", parts: 2)
      assert {:ok, _} = Base.url_decode64(payload, padding: false)
      assert {:ok, _} = Base.url_decode64(mac, padding: false)
    end

    test "different keys produce different tokens" do
      refute Attached.Web.Signer.sign("key1") == Attached.Web.Signer.sign("key2")
    end

    test "same key produces different tokens over time (different expiry)" do
      t1 = Attached.Web.Signer.sign("key", expires_in: 100)
      t2 = Attached.Web.Signer.sign("key", expires_in: 200)
      refute t1 == t2
    end
  end

  describe "verify/1" do
    test "returns {:ok, key} for a valid token" do
      token = Attached.Web.Signer.sign("abc123")
      assert {:ok, "abc123"} = Attached.Web.Signer.verify(token)
    end

    test "returns {:ok, key} for a variant key" do
      key = "variants/abc123/deadbeef"
      token = Attached.Web.Signer.sign(key)
      assert {:ok, ^key} = Attached.Web.Signer.verify(token)
    end

    test "returns error for a tampered mac" do
      token = Attached.Web.Signer.sign("abc123")
      [payload, _mac] = String.split(token, ".", parts: 2)
      tampered = payload <> "." <> "badsignature"
      assert {:error, _} = Attached.Web.Signer.verify(tampered)
    end

    test "returns error for a tampered payload" do
      token = Attached.Web.Signer.sign("abc123")
      [_payload, mac] = String.split(token, ".", parts: 2)
      fake_payload = Base.url_encode64("otherkey|9999999999", padding: false)
      tampered = fake_payload <> "." <> mac
      assert {:error, _} = Attached.Web.Signer.verify(tampered)
    end

    test "returns error for an expired token" do
      token = Attached.Web.Signer.sign("abc123", expires_in: -1)
      assert {:error, :expired_or_invalid} = Attached.Web.Signer.verify(token)
    end

    test "returns error for garbage input" do
      assert {:error, _} = Attached.Web.Signer.verify("not.a.valid.token")
      assert {:error, _} = Attached.Web.Signer.verify("garbage")
    end
  end

  describe "without secret_key_base configured" do
    setup do
      Application.delete_env(:attached, :secret_key_base)
      on_exit(fn -> Application.put_env(:attached, :secret_key_base, @secret) end)
      :ok
    end

    test "sign/1 returns a Base64url-encoded key (no HMAC, always single segment)" do
      token = Attached.Web.Signer.sign("rawkey")
      assert token == Base.url_encode64("rawkey", padding: false)
      refute String.contains?(token, "/")
    end

    test "sign/1 encodes variant keys without slashes" do
      token = Attached.Web.Signer.sign("variants/abc/digest")
      refute String.contains?(token, "/")
    end

    test "verify/1 decodes the Base64url token and returns {:ok, key}" do
      token = Attached.Web.Signer.sign("rawkey")
      assert {:ok, "rawkey"} = Attached.Web.Signer.verify(token)
    end

    test "verify/1 returns error for invalid Base64" do
      assert {:error, :invalid} = Attached.Web.Signer.verify("not valid base64!!!")
    end
  end
end
