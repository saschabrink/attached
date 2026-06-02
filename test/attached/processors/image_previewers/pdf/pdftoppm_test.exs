defmodule Attached.Processors.ImagePreviewers.Pdf.PdftoppmTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.ImagePreviewers.Pdf.Pdftoppm
  alias Attached.Test.ImagePreviewerFixtures

  @pdftoppm_available not is_nil(System.find_executable("pdftoppm"))

  setup do
    output =
      Path.join(System.tmp_dir!(), "pdftoppm_test_#{System.unique_integer([:positive])}.png")

    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  test "accept? returns true for application/pdf and false for non-PDF" do
    assert Pdftoppm.accept?("application/pdf")
    refute Pdftoppm.accept?("image/png")
  end

  @tag skip: not @pdftoppm_available
  test "preview generates output image", %{output: output} do
    input = ImagePreviewerFixtures.minimal_pdf_path()
    on_exit(fn -> File.rm(input) end)
    assert :ok = Pdftoppm.preview(input, output)
    assert File.exists?(output)
  end
end
