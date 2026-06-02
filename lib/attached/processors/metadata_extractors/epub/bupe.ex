defmodule Attached.Processors.MetadataExtractors.Epub.Bupe do
  @moduledoc """
  Extracts EPUB metadata via the [`bupe`](https://hex.pm/packages/bupe)
  package. Pure Elixir, no system dependency.

  Returned fields (only those present in the EPUB are included):
    `:title`, `:creator`, `:contributor`, `:publisher`, `:language`,
    `:identifier`, `:date`, `:description`, `:subject`, `:rights`,
    `:source`, `:pages`.

  `:pages` is the number of items in the EPUB spine (chapter count),
  not a word/page count.
  """

  @behaviour Attached.Processors.MetadataExtractors.Behaviour

  @compile {:no_warn_undefined, [BUPE]}

  @epub_types ~w(application/epub+zip)

  @fields ~w(title creator contributor publisher language identifier
             date description subject rights source)a

  @impl true
  def accept?(content_type), do: content_type in @epub_types

  @impl true
  def available?, do: Code.ensure_loaded?(BUPE)

  @impl true
  def install_hint do
    ~s|Add `{:bupe, "~> 0.6"}` to mix.exs deps. Pure Elixir, no system package needed.|
  end

  @impl true
  def metadata(input_path) do
    try do
      config = BUPE.parse(input_path)

      @fields
      |> Enum.reduce(%{}, fn field, acc ->
        case Map.get(config, field) do
          nil -> acc
          "" -> acc
          [] -> acc
          value -> Map.put(acc, field, value)
        end
      end)
      |> maybe_add_pages(config)
    rescue
      _ -> %{}
    end
  end

  defp maybe_add_pages(meta, config) do
    case Map.get(config, :pages) do
      pages when is_list(pages) and pages != [] -> Map.put(meta, :pages, length(pages))
      _ -> meta
    end
  end
end
