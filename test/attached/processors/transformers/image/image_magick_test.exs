defmodule Attached.Processors.Transformers.Image.ImageMagickTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.Transformers.Image.ImageMagick

  @fixture_png Path.expand("../../../../support/fixtures/header.png", __DIR__)

  @available is_binary(System.find_executable("magick")) or
               is_binary(System.find_executable("convert"))

  setup do
    output =
      Path.join(
        System.tmp_dir!(),
        "image_magick_test_#{System.unique_integer([:positive])}.png"
      )

    on_exit(fn -> File.rm(output) end)
    {:ok, input: @fixture_png, output: output}
  end

  defp tmp_webp do
    path =
      Path.join(
        System.tmp_dir!(),
        "image_magick_quality_#{System.unique_integer([:positive])}.webp"
      )

    on_exit(fn -> File.rm(path) end)
    path
  end

  @tag skip: not @available
  test "resize_to_limit produces output file", %{input: input, output: output} do
    assert :ok = ImageMagick.transform(input, [resize_to_limit: {100, 100}], output)
    assert File.exists?(output)
  end

  @tag skip: not @available
  test "resize_to_fill produces output file", %{input: input, output: output} do
    assert :ok = ImageMagick.transform(input, [resize_to_fill: {50, 50}], output)
    assert File.exists?(output)
  end

  @tag skip: not @available
  test "rotate produces output file", %{input: input, output: output} do
    assert :ok = ImageMagick.transform(input, [rotate: 90], output)
    assert File.exists?(output)
  end

  @tag skip: not @available
  test "returns error for missing input file", %{output: output} do
    assert {:error, _reason} = ImageMagick.transform("/nonexistent/input.png", [], output)
  end

  @tag skip: not @available
  test "lower quality produces a smaller webp", %{input: input} do
    low = tmp_webp()
    high = tmp_webp()

    :ok = ImageMagick.transform(input, [quality: 30], low)
    :ok = ImageMagick.transform(input, [quality: 95], high)

    assert File.stat!(low).size < File.stat!(high).size
  end

  describe "watermark" do
    @base_value 80
    @logo_value 240

    defp magick_bin, do: System.find_executable("magick") || System.find_executable("convert")

    defp solid_png(value, w, h) do
      path =
        Path.join(System.tmp_dir!(), "im_wm_#{System.unique_integer([:positive])}.png")

      {_, 0} =
        System.cmd(magick_bin(), [
          "-size",
          "#{w}x#{h}",
          "xc:rgb(#{value},#{value},#{value})",
          path
        ])

      on_exit(fn -> File.rm(path) end)
      path
    end

    defp tmp_png do
      path =
        Path.join(System.tmp_dir!(), "im_wm_out_#{System.unique_integer([:positive])}.png")

      on_exit(fn -> File.rm(path) end)
      path
    end

    # Reads the red channel (0–255) of a single pixel via ImageMagick's fx.
    defp red(path, x, y) do
      {out, 0} =
        System.cmd(magick_bin(), [
          "#{path}[1x1+#{x}+#{y}]",
          "-format",
          "%[fx:int(255*r+0.5)]",
          "info:"
        ])

      out |> String.trim() |> String.to_integer()
    end

    setup do
      base = solid_png(@base_value, 200, 150)
      logo = solid_png(@logo_value, 40, 20)
      {:ok, base: base, logo: logo}
    end

    @tag skip: not @available
    test "composites the overlay only in the anchored corner", %{base: base, logo: logo} do
      out = tmp_png()

      :ok =
        ImageMagick.transform(
          base,
          [watermark: [path: logo, gravity: :south_east, margin: 5]],
          out
        )

      # Logo (40x20) sits at the bottom-right inset by 5px: x 155..195, y 125..145.
      assert_in_delta red(out, 175, 135), @logo_value, 2
      # The opposite corner is untouched.
      assert_in_delta red(out, 10, 10), @base_value, 2
    end

    @tag skip: not @available
    test "opacity blends the overlay into the base", %{base: base, logo: logo} do
      out = tmp_png()

      :ok =
        ImageMagick.transform(
          base,
          [watermark: [path: logo, gravity: :south_east, margin: 5, opacity: 0.5]],
          out
        )

      # 0.5 * 240 (logo) + 0.5 * 80 (base) = 160.
      assert_in_delta red(out, 175, 135), 160, 2
    end

    @tag skip: not @available
    test "scale sizes the overlay relative to the base width", %{base: base, logo: logo} do
      out = tmp_png()

      # 0.5 * 200 = 100px wide, anchored top-left at the origin (x 0..100).
      :ok =
        ImageMagick.transform(
          base,
          [watermark: [path: logo, gravity: :north_west, scale: 0.5]],
          out
        )

      # At native 40px width this pixel would be plain base; scaling paints it.
      assert_in_delta red(out, 90, 10), @logo_value, 2
    end

    @tag skip: not @available
    test "is anchored independently per gravity", %{base: base, logo: logo} do
      out = tmp_png()

      :ok = ImageMagick.transform(base, [watermark: [path: logo, gravity: :north_west]], out)

      assert_in_delta red(out, 10, 5), @logo_value, 2
      assert_in_delta red(out, 190, 145), @base_value, 2
    end

    @tag skip: not @available
    test "margin accepts a {horizontal, vertical} tuple", %{base: base, logo: logo} do
      out = tmp_png()

      # 20px right inset, 5px bottom inset -> logo (40x20) top-left at (140, 125).
      :ok =
        ImageMagick.transform(
          base,
          [watermark: [path: logo, gravity: :south_east, margin: {20, 5}]],
          out
        )

      assert_in_delta red(out, 142, 127), @logo_value, 2
      # Just left of the overlay (right inset is 20px).
      assert_in_delta red(out, 137, 127), @base_value, 2
      # Just above the overlay (bottom inset is only 5px).
      assert_in_delta red(out, 142, 122), @base_value, 2
    end

    @tag skip: not @available
    test "raises when :path is missing", %{base: base} do
      assert_raise KeyError, fn ->
        ImageMagick.transform(base, [watermark: [gravity: :south_east]], tmp_png())
      end
    end

    # A relative path is joined onto the app dir of the configured repo's app
    # (Attached.TestRepo -> :attached here), so a file under the app resolves at
    # runtime without depending on the cwd.
    @tag skip: not @available
    test "resolves a relative watermark path against the app dir", %{base: base, logo: logo} do
      rel = "wm_rel_#{System.unique_integer([:positive])}.png"
      dest = Application.app_dir(:attached, rel)
      File.cp!(logo, dest)
      on_exit(fn -> File.rm(dest) end)

      out = tmp_png()

      :ok =
        ImageMagick.transform(
          base,
          [watermark: [path: rel, gravity: :south_east, margin: 5]],
          out
        )

      assert_in_delta red(out, 175, 135), @logo_value, 2
    end
  end
end
