defmodule Attached.Processors.Transformers.Image.ImageMagick do
  @moduledoc """
  Image transformer backed by ImageMagick via the `convert` (v6) or `magick` (v7) CLI.

  No Elixir package required — only the `imagemagick` system package.

  ## Configuration

      config :attached,
        transformers: [Attached.Processors.Transformers.Image.ImageMagick]

  Optionally override the binary path:

      config :attached,
        image_magick: [bin: "/usr/local/bin/magick"]
  """

  @behaviour Attached.Processors.Transformers.Behaviour

  @impl true
  def accept?("image/" <> _, "image/" <> _), do: true
  def accept?(_, _), do: false

  @impl true
  def available?, do: not is_nil(detect_cmd_path())

  @impl true
  def install_hint do
    "Install ImageMagick: `brew install imagemagick`, `apt install imagemagick`, or `nix-shell -p imagemagick`. Auto-detects the `magick` (v7) or `convert` (v6) binary on PATH."
  end

  @impl true
  def transform(input_path, transforms, output_path) do
    base_width = if scaled_watermark?(transforms), do: identify_width(input_path)

    args =
      [input_path] ++
        build_args(transforms, base_width) ++ quality_args(transforms) ++ [output_path]

    try do
      case System.cmd(cmd(), args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, code} -> {:error, "ImageMagick exited with code #{code}: #{output}"}
      end
    rescue
      ErlangError -> {:error, "ImageMagick not found — install imagemagick"}
    end
  end

  defp build_args(transforms, base_width) do
    Enum.flat_map(transforms, fn
      {:resize_to_fill, {w, h}} ->
        ["-resize", "#{w}x#{h}^", "-gravity", "Center", "-extent", "#{w}x#{h}"]

      {:resize_to_limit, {w, h}} ->
        ["-resize", "#{w}x#{h}>"]

      {:resize_to_fit, {w, h}} ->
        ["-resize", "#{w}x#{h}"]

      {:resize_and_pad, {w, h}} ->
        [
          "-resize",
          "#{w}x#{h}",
          "-background",
          "transparent",
          "-gravity",
          "Center",
          "-extent",
          "#{w}x#{h}"
        ]

      {:crop, {x, y, w, h}} ->
        ["-crop", "#{w}x#{h}+#{x}+#{y}", "+repage"]

      {:rotate, degrees} ->
        ["-rotate", "#{degrees}"]

      {:watermark, opts} ->
        watermark_args(opts, base_width)

      _unknown ->
        []
    end)
  end

  # Composites an overlay image onto the (already-resized) base. The overlay is
  # loaded in its own `( ... )` group so an optional resize applies only to it;
  # `-gravity`/`-geometry` anchor it and `-composite` blends it on. Opacity below
  # 1.0 switches the compose mode to `dissolve`, which scales the overlay's alpha.
  defp watermark_args(opts, base_width) do
    path = opts |> Keyword.fetch!(:path) |> resolve_path()
    gravity = opts |> Keyword.get(:gravity, :south_east) |> gravity_name()
    {mx, my} = margin_xy(Keyword.get(opts, :margin, 0))
    opacity = Keyword.get(opts, :opacity, 1.0)
    scale = Keyword.get(opts, :scale)

    overlay = ["(", path] ++ overlay_resize(scale, base_width) ++ [")"]

    overlay ++
      ["-gravity", gravity, "-geometry", "+#{mx}+#{my}"] ++
      compose_args(opacity) ++ ["-composite"]
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

  defp margin_xy(margin) when is_integer(margin), do: {margin, margin}
  defp margin_xy({x, y}) when is_integer(x) and is_integer(y), do: {x, y}

  defp overlay_resize(nil, _base_width), do: []
  defp overlay_resize(_scale, nil), do: []

  defp overlay_resize(scale, base_width) when is_number(scale) and scale > 0 do
    target = max(round(base_width * scale), 1)
    ["-resize", "#{target}x"]
  end

  defp compose_args(opacity) when is_number(opacity) and opacity >= 1.0,
    do: ["-compose", "over"]

  defp compose_args(opacity) when is_number(opacity) do
    pct = opacity |> Kernel.*(100) |> round() |> max(0) |> min(100)
    ["-compose", "dissolve", "-define", "compose:args=#{pct}"]
  end

  defp gravity_name(:north_west), do: "NorthWest"
  defp gravity_name(:north), do: "North"
  defp gravity_name(:north_east), do: "NorthEast"
  defp gravity_name(:west), do: "West"
  defp gravity_name(:center), do: "Center"
  defp gravity_name(:east), do: "East"
  defp gravity_name(:south_west), do: "SouthWest"
  defp gravity_name(:south), do: "South"
  defp gravity_name(:south_east), do: "SouthEast"

  defp scaled_watermark?(transforms) do
    Enum.any?(transforms, fn
      {:watermark, opts} -> not is_nil(Keyword.get(opts, :scale))
      _ -> false
    end)
  end

  defp identify_width(path) do
    {bin, prefix} = identify_cmd()

    case System.cmd(bin, prefix ++ ["-format", "%w", path], stderr_to_stdout: true) do
      {out, 0} -> out |> String.split() |> List.first() |> String.to_integer()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # v7 exposes `identify` as a `magick` subcommand; v6 ships a separate binary.
  defp identify_cmd do
    bin = cmd()

    if Path.basename(bin) == "magick" do
      {bin, ["identify"]}
    else
      {System.find_executable("identify") || "identify", []}
    end
  end

  defp quality_args(transforms) do
    case Keyword.get(transforms, :quality) do
      n when is_integer(n) -> ["-quality", Integer.to_string(n)]
      _ -> []
    end
  end

  defp cmd do
    case Application.get_env(:attached, :image_magick, []) |> Keyword.get(:bin) do
      nil -> detect_cmd_path() || "convert"
      path -> path
    end
  end

  # ImageMagick 7 uses `magick`, v6 uses `convert`
  defp detect_cmd_path do
    System.find_executable("magick") || System.find_executable("convert")
  end
end
