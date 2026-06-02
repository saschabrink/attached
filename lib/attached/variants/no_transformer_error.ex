defmodule Attached.Variants.NoTransformerError do
  @moduledoc """
  Raised when no transformer (direct or via the image previewer fallback) is
  available to produce a variant for the given content-type pair.

  This is a configuration/install problem, not a runtime failure:
  either the `:transformers` config does not include a module that
  accepts the pair, or the required system dependencies (libvips,
  imagemagick, ffmpeg, poppler, mupdf, …) are not installed on the host.
  """

  defexception [:message]

  @impl true
  def exception(opts) do
    source = Keyword.fetch!(opts, :source)
    target = Keyword.fetch!(opts, :target)
    %__MODULE__{message: build_message(source, target)}
  end

  defp build_message(source, target) do
    """
    Cannot transform variant: #{source} → #{target}.

    No configured transformer accepts this content-type pair, and no
    fallback path (image previewer → image transformer) is available either.

    Check:
      * `config :attached, :transformers` includes a module whose
        `accept?/2` returns true for this pair
      * for non-image → image variants, an image previewer for #{source} is
        available (install poppler/mupdf for PDF, ffmpeg for video)
      * system dependencies for the configured transformers are
        installed (libvips for Vix, imagemagick for ImageMagick)
    """
    |> String.trim_trailing()
  end
end
