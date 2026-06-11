defmodule Attached.Processors.Transformers.Image.VixTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.Transformers.Image.Vix, as: Transformer
  alias Vix.Vips.{Image, Operation}

  @fixture_png Path.expand("../../../../support/fixtures/header.png", __DIR__)

  @available Code.ensure_loaded?(Vix.Vips.Image)

  setup do
    {:ok, input: @fixture_png}
  end

  defp tmp_webp do
    path =
      Path.join(
        System.tmp_dir!(),
        "vix_quality_#{System.unique_integer([:positive])}.webp"
      )

    on_exit(fn -> File.rm(path) end)
    path
  end

  @tag skip: not @available
  test "lower quality produces a smaller webp", %{input: input} do
    low = tmp_webp()
    high = tmp_webp()

    :ok = Transformer.transform(input, [quality: 30], low)
    :ok = Transformer.transform(input, [quality: 95], high)

    assert File.stat!(low).size < File.stat!(high).size
  end

  describe "resize_and_pad" do
    @tag skip: not @available
    test "pads to the exact target dimensions with a transparent background" do
      base = solid_png(80.0, 200, 150)
      out = tmp_png()

      :ok = Transformer.transform(base, [resize_and_pad: {100, 100}], out)

      {:ok, img} = Image.new_from_file(out)
      assert Image.width(img) == 100
      assert Image.height(img) == 100

      # 200×150 fits to 100×75, centered: ~12px padding bands top and bottom.
      # The alpha band is 0 in the padding and 255 inside the image.
      assert List.last(Operation.getpoint!(img, 50, 2)) == 0.0
      assert List.last(Operation.getpoint!(img, 50, 50)) == 255.0
    end
  end

  describe "watermark" do
    @base_value 80.0
    @logo_value 240.0

    # A solid grayscale PNG. Going through PNG tags the image as sRGB, which is
    # what real uploads look like — synthetic in-memory images carry a
    # "multiband" interpretation that the compositing colourspace can't route.
    defp solid_png(value, w, h) do
      path =
        Path.join(System.tmp_dir!(), "vix_wm_#{System.unique_integer([:positive])}.png")

      img =
        Operation.black!(w, h, bands: 3)
        |> Operation.linear!([1.0], [value])
        |> Operation.copy!(interpretation: :VIPS_INTERPRETATION_sRGB)

      :ok = Image.write_to_file(img, path)
      on_exit(fn -> File.rm(path) end)
      path
    end

    defp tmp_png do
      path =
        Path.join(System.tmp_dir!(), "vix_wm_out_#{System.unique_integer([:positive])}.png")

      on_exit(fn -> File.rm(path) end)
      path
    end

    defp red(path, x, y) do
      {:ok, img} = Image.new_from_file(path)
      [r | _] = Operation.getpoint!(img, x, y)
      r
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
        Transformer.transform(
          base,
          [watermark: [path: logo, gravity: :south_east, margin: 5]],
          out
        )

      # Logo (40x20) sits at the bottom-right inset by 5px: x 155..195, y 125..145.
      assert_in_delta red(out, 175, 135), @logo_value, 1.0
      # The opposite corner is untouched.
      assert_in_delta red(out, 10, 10), @base_value, 1.0
    end

    @tag skip: not @available
    test "opacity blends the overlay into the base", %{base: base, logo: logo} do
      out = tmp_png()

      :ok =
        Transformer.transform(
          base,
          [watermark: [path: logo, gravity: :south_east, margin: 5, opacity: 0.5]],
          out
        )

      # 0.5 * 240 (logo) + 0.5 * 80 (base) = 160.
      assert_in_delta red(out, 175, 135), 160.0, 1.0
    end

    @tag skip: not @available
    test "scale sizes the overlay relative to the base width", %{base: base, logo: logo} do
      out = tmp_png()

      # 0.5 * 200 = 100px wide, anchored top-left at the origin (x 0..100).
      :ok =
        Transformer.transform(
          base,
          [watermark: [path: logo, gravity: :north_west, scale: 0.5]],
          out
        )

      # At native 40px width this pixel would be plain base; scaling paints it.
      assert_in_delta red(out, 90, 10), @logo_value, 1.0
    end

    @tag skip: not @available
    test "is anchored independently per gravity", %{base: base, logo: logo} do
      out = tmp_png()

      :ok = Transformer.transform(base, [watermark: [path: logo, gravity: :north_west]], out)

      assert_in_delta red(out, 10, 5), @logo_value, 1.0
      assert_in_delta red(out, 190, 145), @base_value, 1.0
    end

    @tag skip: not @available
    test "margin accepts a {horizontal, vertical} tuple", %{base: base, logo: logo} do
      out = tmp_png()

      # 20px right inset, 5px bottom inset -> logo (40x20) top-left at (140, 125).
      :ok =
        Transformer.transform(
          base,
          [watermark: [path: logo, gravity: :south_east, margin: {20, 5}]],
          out
        )

      assert_in_delta red(out, 141, 126), @logo_value, 1.0
      # Just left of the overlay (right inset is 20px).
      assert_in_delta red(out, 139, 126), @base_value, 1.0
      # Just above the overlay (bottom inset is only 5px).
      assert_in_delta red(out, 141, 124), @base_value, 1.0
    end

    @tag skip: not @available
    test "raises when :path is missing", %{base: base} do
      assert_raise KeyError, fn ->
        Transformer.transform(base, [watermark: [gravity: :south_east]], tmp_png())
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
        Transformer.transform(
          base,
          [watermark: [path: rel, gravity: :south_east, margin: 5]],
          out
        )

      assert_in_delta red(out, 175, 135), @logo_value, 1.0
    end
  end
end
