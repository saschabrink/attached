defmodule Attached.StorageBackends.S3.SignatureTest do
  use ExUnit.Case, async: true

  alias Attached.StorageBackends.S3.Signature

  # The official AWS SigV4 examples from
  # https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
  # and sigv4-query-string-auth.html — expected signatures are taken verbatim
  # from the documentation.

  @creds %{
    access_key_id: "AKIAIOSFODNN7EXAMPLE",
    secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    region: "us-east-1",
    session_token: nil
  }

  @datetime {{2013, 5, 24}, {0, 0, 0}}

  describe "sign_headers/6 against the AWS example vectors" do
    test "GET object with a range header" do
      headers =
        Signature.sign_headers(
          @creds,
          @datetime,
          "GET",
          "https://examplebucket.s3.amazonaws.com/test.txt",
          [{"range", "bytes=0-9"}],
          ""
        )

      assert {"authorization", authorization} = List.keyfind(headers, "authorization", 0)

      assert authorization ==
               "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request," <>
                 "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date," <>
                 "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"

      assert {"x-amz-date", "20130524T000000Z"} = List.keyfind(headers, "x-amz-date", 0)
      assert {"host", "examplebucket.s3.amazonaws.com"} = List.keyfind(headers, "host", 0)
    end

    test "PUT object with a body and a path needing encoding" do
      headers =
        Signature.sign_headers(
          @creds,
          @datetime,
          "PUT",
          "https://examplebucket.s3.amazonaws.com/test$file.text",
          [{"date", "Fri, 24 May 2013 00:00:00 GMT"}, {"x-amz-storage-class", "REDUCED_REDUNDANCY"}],
          "Welcome to Amazon S3."
        )

      assert {"authorization", authorization} = List.keyfind(headers, "authorization", 0)

      assert authorization ==
               "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request," <>
                 "SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class," <>
                 "Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd"
    end

    test "GET bucket lifecycle — query param without a value" do
      headers =
        Signature.sign_headers(
          @creds,
          @datetime,
          "GET",
          "https://examplebucket.s3.amazonaws.com?lifecycle",
          [],
          ""
        )

      assert {"authorization", authorization} = List.keyfind(headers, "authorization", 0)

      assert authorization =~
               "Signature=fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543"
    end

    test "GET bucket list — multiple query params, sorted canonically" do
      headers =
        Signature.sign_headers(
          @creds,
          @datetime,
          "GET",
          "https://examplebucket.s3.amazonaws.com?max-keys=2&prefix=J",
          [],
          ""
        )

      assert {"authorization", authorization} = List.keyfind(headers, "authorization", 0)

      assert authorization =~
               "Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7"
    end
  end

  describe "presign_url/5 against the AWS example vector" do
    test "presigned GET object, 24h expiry" do
      url =
        Signature.presign_url(
          @creds,
          @datetime,
          "GET",
          "https://examplebucket.s3.amazonaws.com/test.txt",
          86400
        )

      assert url ==
               "https://examplebucket.s3.amazonaws.com/test.txt" <>
                 "?X-Amz-Algorithm=AWS4-HMAC-SHA256" <>
                 "&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request" <>
                 "&X-Amz-Date=20130524T000000Z" <>
                 "&X-Amz-Expires=86400" <>
                 "&X-Amz-SignedHeaders=host" <>
                 "&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
    end
  end

  describe "presign_url/6 with extra signed headers" do
    test "lists the headers in X-Amz-SignedHeaders, sorted" do
      url =
        Signature.presign_url(
          @creds,
          @datetime,
          "PUT",
          "https://examplebucket.s3.amazonaws.com/test.txt",
          300,
          [{"content-md5", "abc"}, {"content-type", "text/plain"}]
        )

      assert url =~ "X-Amz-SignedHeaders=content-md5%3Bcontent-type%3Bhost"
    end

    test "the signature covers the header values" do
      presign = fn md5 ->
        Signature.presign_url(
          @creds,
          @datetime,
          "PUT",
          "https://examplebucket.s3.amazonaws.com/test.txt",
          300,
          [{"content-md5", md5}]
        )
      end

      [sig_a, sig_b] =
        for url <- [presign.("aaa"), presign.("bbb")] do
          [sig] = Regex.run(~r/X-Amz-Signature=([0-9a-f]+)/, url, capture: :all_but_first)
          sig
        end

      refute sig_a == sig_b
    end
  end

  describe "non-vector properties" do
    test "non-default ports are part of the signed host" do
      url = Signature.presign_url(@creds, @datetime, "GET", "http://localhost:9000/bucket/key", 300)
      assert url =~ "http://localhost:9000/bucket/key?"
    end

    test "existing query params are preserved and signed" do
      url =
        Signature.presign_url(
          @creds,
          @datetime,
          "GET",
          "https://examplebucket.s3.amazonaws.com/test.txt?response-content-type=image%2Fpng",
          300
        )

      assert url =~ "response-content-type=image%2Fpng&X-Amz-Algorithm="
    end

    test "a session token becomes a signed X-Amz-Security-Token param" do
      creds = %{@creds | session_token: "the-token"}
      url = Signature.presign_url(creds, @datetime, "GET", "https://examplebucket.s3.amazonaws.com/test.txt", 300)

      assert url =~ "X-Amz-Security-Token=the-token"
      assert url =~ "X-Amz-Signature="
    end
  end
end
