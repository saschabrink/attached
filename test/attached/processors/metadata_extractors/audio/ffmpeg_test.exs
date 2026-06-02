defmodule Attached.Processors.MetadataExtractors.Audio.FFmpegTest do
  use ExUnit.Case, async: true

  @ffprobe_available not is_nil(System.find_executable("ffprobe"))
  @ffmpeg_available not is_nil(System.find_executable("ffmpeg"))

  describe "accept?/1" do
    test "returns true for audio content types" do
      assert Attached.Processors.MetadataExtractors.Audio.FFmpeg.accept?("audio/mpeg")
      assert Attached.Processors.MetadataExtractors.Audio.FFmpeg.accept?("audio/ogg")
    end

    test "returns false for non-audio content types" do
      refute Attached.Processors.MetadataExtractors.Audio.FFmpeg.accept?("image/png")
      refute Attached.Processors.MetadataExtractors.Audio.FFmpeg.accept?("video/mp4")
    end
  end

  describe "metadata/1" do
    @tag skip: not (@ffprobe_available and @ffmpeg_available)
    test "extracts duration and bit_rate" do
      path = generate_test_audio()
      on_exit(fn -> File.rm(path) end)

      meta = Attached.Processors.MetadataExtractors.Audio.FFmpeg.metadata(path)
      assert meta[:duration] > 0
      assert meta[:bit_rate] > 0
    end
  end

  defp generate_test_audio do
    path =
      Path.join(System.tmp_dir!(), "audio_extractor_#{System.unique_integer([:positive])}.mp3")

    System.cmd("ffmpeg", ~w(-f lavfi -i sine=frequency=440:duration=1 -y) ++ [path], stderr_to_stdout: true)

    path
  end
end
