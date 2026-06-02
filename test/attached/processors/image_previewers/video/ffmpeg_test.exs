defmodule Attached.Processors.ImagePreviewers.Video.FFmpegTest do
  use ExUnit.Case, async: true

  alias Attached.Processors.ImagePreviewers.Video.FFmpeg

  @ffmpeg_available not is_nil(System.find_executable("ffmpeg"))

  setup do
    output =
      Path.join(System.tmp_dir!(), "ffmpeg_previewer_test_#{System.unique_integer([:positive])}.png")

    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  test "accept? returns true for video/mp4 and false for non-video" do
    assert FFmpeg.accept?("video/mp4")
    refute FFmpeg.accept?("image/png")
  end

  @tag skip: not @ffmpeg_available
  test "preview generates output image", %{output: output} do
    input = generate_test_video()
    on_exit(fn -> File.rm(input) end)
    assert :ok = FFmpeg.preview(input, output)
    assert File.exists?(output)
  end

  defp generate_test_video do
    path =
      Path.join(System.tmp_dir!(), "ffmpeg_previewer_test_#{System.unique_integer([:positive])}.mp4")

    System.cmd(
      "ffmpeg",
      ~w(-f lavfi -i color=c=red:size=64x64:rate=1 -t 1 -y) ++ [path],
      stderr_to_stdout: true
    )

    path
  end
end
