defmodule Attached.StorageBackends.S3.XML do
  @moduledoc false

  # Minimal value extraction for S3's ListObjectsV2 response. Not a general
  # XML parser — the response is flat, machine-generated

  @doc "Returns the text content of every `<tag>...</tag>` occurrence."
  def text_values(xml, tag) do
    ~r|<#{tag}>(.*?)</#{tag}>|s
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.map(fn [value] -> unescape(value) end)
  end

  @doc "Returns the text content of the first `<tag>...</tag>`, or `nil`."
  def text_value(xml, tag) do
    case text_values(xml, tag) do
      [value | _] -> value
      [] -> nil
    end
  end

  # The five predefined XML entities; &amp; last so it doesn't re-expand.
  defp unescape(value) do
    value
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end
end
