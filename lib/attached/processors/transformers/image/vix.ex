defmodule Attached.Processors.Transformers.Image.Vix do
  @moduledoc """
  Image transformer backed by libvips via the `vix` package.

  This is the default transformer.
  """

  @behaviour Attached.Processors.Transformers.Behaviour

  @compile {:no_warn_undefined, [Vix.Vips.Image, Vix.Vips.Operation]}

  @impl true
  def accept?("image/" <> _, "image/" <> _), do: true
  def accept?(_, _), do: false

  @impl true
  def available?, do: Code.ensure_loaded?(Vix.Vips.Image)

  @impl true
  def install_hint do
    ~s|Add `{:vix, "~> 0.31"}` to mix.exs deps — ships with a precompiled libvips NIF, no system packages needed.|
  end

  @impl true
  def transform(input_path, transforms, output_path) do
    {:ok, image} = Vix.Vips.Image.new_from_file(input_path)
    image = apply_transforms(image, transforms)
    :ok = Vix.Vips.Image.write_to_file(image, output_path <> save_opts(output_path, transforms))
    :ok
  end

  # libvips accepts save options as a path suffix, e.g. `out.webp[Q=80]`.
  # Quality is meaningful for jpeg/webp/gif; other formats ignore it.
  defp save_opts(output_path, transforms) do
    quality = Keyword.get(transforms, :quality)
    ext = output_path |> Path.extname() |> String.downcase()

    if is_integer(quality) and ext in [".jpg", ".jpeg", ".webp", ".gif"] do
      "[Q=#{quality}]"
    else
      ""
    end
  end

  defp apply_transforms(image, transforms) do
    Enum.reduce(transforms, image, fn
      {:resize_to_fill, {w, h}}, img ->
        Vix.Vips.Operation.thumbnail_image!(img, w, height: h, crop: :VIPS_INTERESTING_CENTRE)

      {:resize_to_limit, {w, h}}, img ->
        Vix.Vips.Operation.thumbnail_image!(img, w, height: h, size: :VIPS_SIZE_DOWN)

      {:resize_to_fit, {w, h}}, img ->
        Vix.Vips.Operation.thumbnail_image!(img, w, height: h, size: :VIPS_SIZE_BOTH)

      {:resize_and_pad, {w, h}}, img ->
        Vix.Vips.Operation.thumbnail_image!(img, w, height: h, size: :VIPS_SIZE_BOTH)

      {:crop, {x, y, w, h}}, img ->
        Vix.Vips.Operation.extract_area!(img, x, y, w, h)

      {:rotate, degrees}, img ->
        Vix.Vips.Operation.rotate!(img, degrees)

      {:watermark, opts}, img ->
        apply_watermark(img, opts)

      _unknown, img ->
        img
    end)
  end

  # Composites an overlay image (logo, badge) onto the base.
  #
  # Options:
  #   * `:path`    — file path of the overlay image (required)
  #   * `:gravity` — corner/edge to anchor to (default `:south_east`); one of
  #     `:north_west`, `:north`, `:north_east`, `:west`, `:center`, `:east`,
  #     `:south_west`, `:south`, `:south_east`
  #   * `:margin`  — inset in pixels from the anchored edges (default `0`);
  #     an integer for a uniform inset, or `{horizontal, vertical}` for
  #     independent right/left and top/bottom insets
  #   * `:opacity` — `0.0`–`1.0`, multiplied into the overlay's alpha (default `1.0`)
  #   * `:scale`   — overlay width as a fraction of the base width (e.g. `0.2`);
  #     omit to keep the overlay's native size
  #
  # Both images are normalised to sRGB with an alpha channel so their band
  # counts match — libvips composite requires it.
  defp apply_watermark(base, opts) do
    path = opts |> Keyword.fetch!(:path) |> resolve_path()
    gravity = Keyword.get(opts, :gravity, :south_east)
    margin = Keyword.get(opts, :margin, 0)
    opacity = Keyword.get(opts, :opacity, 1.0)
    scale = Keyword.get(opts, :scale)

    {:ok, overlay} = Vix.Vips.Image.new_from_file(path)

    base = to_srgb_alpha(base)

    overlay =
      overlay
      |> to_srgb_alpha()
      |> scale_overlay(base, scale)
      |> apply_opacity(opacity)

    {x, y} = position(base, overlay, gravity, margin)

    Vix.Vips.Operation.composite2!(base, overlay, :VIPS_BLEND_MODE_OVER, x: x, y: y)
  end

  # Absolute paths pass through; a relative path is joined onto the app's dir at
  # runtime (the way Plug.Static resolves an atom `:from`), so a file stored under
  # priv is found both in dev and in a release. The app defaults to the one owning
  # the configured repo and can be overridden with `config :attached, :otp_app`.
  defp resolve_path(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(Application.app_dir(otp_app()), path)
    end
  end

  defp otp_app do
    Application.get_env(:attached, :otp_app) ||
      Application.get_application(Attached.Repo.current())
  end

  defp to_srgb_alpha(image) do
    image = Vix.Vips.Operation.colourspace!(image, :VIPS_INTERPRETATION_sRGB)

    if Vix.Vips.Image.has_alpha?(image),
      do: image,
      else: Vix.Vips.Operation.bandjoin_const!(image, [255.0])
  end

  defp scale_overlay(overlay, _base, nil), do: overlay

  defp scale_overlay(overlay, base, scale) when is_number(scale) and scale > 0 do
    target_width = max(round(Vix.Vips.Image.width(base) * scale), 1)
    Vix.Vips.Operation.thumbnail_image!(overlay, target_width)
  end

  # opacity >= 1.0 leaves the overlay's own alpha untouched.
  defp apply_opacity(overlay, opacity) when is_number(opacity) and opacity >= 1.0, do: overlay

  defp apply_opacity(overlay, opacity) when is_number(opacity) do
    last = Vix.Vips.Image.bands(overlay) - 1
    colors = Vix.Vips.Operation.extract_band!(overlay, 0, n: last)

    alpha =
      overlay
      |> Vix.Vips.Operation.extract_band!(last)
      |> Vix.Vips.Operation.linear!([opacity], [0.0])

    Vix.Vips.Operation.bandjoin!([colors, alpha])
  end

  defp position(base, overlay, gravity, margin) do
    {mx, my} = margin_xy(margin)

    bw = Vix.Vips.Image.width(base)
    bh = Vix.Vips.Image.height(base)
    ow = Vix.Vips.Image.width(overlay)
    oh = Vix.Vips.Image.height(overlay)

    left = mx
    top = my
    right = bw - ow - mx
    bottom = bh - oh - my
    center_x = div(bw - ow, 2)
    center_y = div(bh - oh, 2)

    case gravity do
      :north_west -> {left, top}
      :north -> {center_x, top}
      :north_east -> {right, top}
      :west -> {left, center_y}
      :center -> {center_x, center_y}
      :east -> {right, center_y}
      :south_west -> {left, bottom}
      :south -> {center_x, bottom}
      :south_east -> {right, bottom}
    end
  end

  defp margin_xy(margin) when is_integer(margin), do: {margin, margin}
  defp margin_xy({x, y}) when is_integer(x) and is_integer(y), do: {x, y}
end
