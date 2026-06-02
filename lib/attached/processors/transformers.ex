defmodule Attached.Processors.Transformers do
  @moduledoc """
  Registry and dispatch for variant transformers.

  Each transformer declares the `(input_content_type, output_content_type)`
  pairs it accepts via `accept?/2`. `Attached.Variants` dispatches by
  matching the original's content type against the variant's declared
  `mime_type:` — an image transformer covers image/* → image/*, a
  hypothetical `attached_ffmpeg` could register audio/mpeg → audio/ogg,
  a custom module can register application/pdf → text/plain.

  Ships with:
  - `Attached.Processors.Transformers.Image.Vix` — libvips via `vix` (default, image/*)
  - `Attached.Processors.Transformers.Image.ImageMagick` — `convert`/`magick` CLI (image/*)
  - `Attached.Processors.Transformers.Document.Pandoc` — pandoc CLI (epub/docx/html/... → text/markdown)

  ## Configuration

  Transformers are tried in order. First `accept?(input, output) == true`
  wins:

      config :attached, transformers: [
        Attached.Processors.Transformers.Image.Vix,
        AttachedFFmpeg.AudioTranscoder,
        MyApp.Transformers.PdfToText
      ]

  ## Supported transforms (built-in image transformers)

  Both `Vix` and `ImageMagick` support the same transform keys:

  | Key | Value | Effect |
  |---|---|---|
  | `:resize_to_fill` | `{w, h}` | Crop to exact dimensions |
  | `:resize_to_limit` | `{w, h}` | Shrink only, preserve aspect ratio |
  | `:resize_to_fit` | `{w, h}` | Fit within bounds, may enlarge |
  | `:resize_and_pad` | `{w, h}` | Fit and pad to exact dimensions |
  | `:crop` | `{x, y, w, h}` | Crop at offset |
  | `:rotate` | degrees | Rotate clockwise |

  ## Non-image transformers

  Custom transformers can target any content-type pair. Example
  (PDF → plain text) — registered in config as above:

      defmodule MyApp.Transformers.PdfToText do
        @behaviour Attached.Processors.Transformers.Behaviour

        @impl true
        def accept?("application/pdf", "text/plain"), do: true
        def accept?(_, _), do: false

        @impl true
        def transform(input_path, _transforms, output_path) do
          case System.cmd("pdftotext", [input_path, output_path]) do
            {_, 0} -> :ok
            {out, code} -> {:error, {:exit, code, out}}
          end
        end
      end
  """

  @doc """
  Returns the first transformer that accepts the given content-type pair
  and whose runtime dependencies are available. `nil` if none match.
  """
  def find_for(input_content_type, output_content_type) do
    Enum.find(list(), fn mod ->
      mod.accept?(input_content_type, output_content_type) and mod.available?()
    end)
  end

  @doc "Returns all configured transformers (regardless of availability)."
  def list do
    Application.get_env(:attached, :transformers, [
      Attached.Processors.Transformers.Image.Vix,
      Attached.Processors.Transformers.Image.ImageMagick,
      Attached.Processors.Transformers.Document.Pandoc
    ])
  end
end
