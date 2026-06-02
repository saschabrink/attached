defmodule Attached.Processors.ImagePreviewers.Pdf.MutoolTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.ImagePreviewers.Pdf.Mutool
  alias Attached.Test.ImagePreviewerFixtures

  @mutool_available not is_nil(System.find_executable("mutool"))

  setup do
    output =
      Path.join(System.tmp_dir!(), "mutool_test_#{System.unique_integer([:positive])}.png")

    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  test "accept? returns true for application/pdf and false for non-PDF" do
    assert Mutool.accept?("application/pdf")
    refute Mutool.accept?("image/png")
  end

  @tag skip: not @mutool_available
  test "preview generates output image", %{output: output} do
    input = ImagePreviewerFixtures.minimal_pdf_path()
    on_exit(fn -> File.rm(input) end)
    assert :ok = Mutool.preview(input, output)
    assert File.exists?(output)
  end
end
