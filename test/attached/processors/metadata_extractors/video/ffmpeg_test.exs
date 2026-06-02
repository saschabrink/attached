defmodule Attached.Processors.MetadataExtractors.Video.FFmpegTest do
  use ExUnit.Case, async: true

  @ffprobe_available not is_nil(System.find_executable("ffprobe"))
  @ffmpeg_available not is_nil(System.find_executable("ffmpeg"))

  describe "accept?/1" do
    test "returns true for video content types" do
      assert Attached.Processors.MetadataExtractors.Video.FFmpeg.accept?("video/mp4")
      assert Attached.Processors.MetadataExtractors.Video.FFmpeg.accept?("video/webm")
    end

    test "returns false for non-video content types" do
      refute Attached.Processors.MetadataExtractors.Video.FFmpeg.accept?("image/png")
      refute Attached.Processors.MetadataExtractors.Video.FFmpeg.accept?("audio/mpeg")
    end
  end

  describe "metadata/1" do
    @tag skip: not (@ffprobe_available and @ffmpeg_available)
    test "extracts width, height, and duration" do
      path = generate_test_video()
      on_exit(fn -> File.rm(path) end)

      meta = Attached.Processors.MetadataExtractors.Video.FFmpeg.metadata(path)
      assert meta[:width] == 64.0
      assert meta[:height] == 64.0
      assert meta[:duration] > 0
      assert meta[:video] == true
    end
  end

  defp generate_test_video do
    path =
      Path.join(System.tmp_dir!(), "video_extractor_#{System.unique_integer([:positive])}.mp4")

    System.cmd("ffmpeg", ~w(-f lavfi -i color=c=red:size=64x64:rate=1 -t 1 -y) ++ [path], stderr_to_stdout: true)

    path
  end
end
