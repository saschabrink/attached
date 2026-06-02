defmodule Attached.Processors.ImagePreviewers.Video.FFmpeg do
  @moduledoc """
  Generates a preview image from the first frame of a video file using `ffmpeg`.
  """

  @behaviour Attached.Processors.ImagePreviewers.Behaviour

  @video_types ~w(video/mp4 video/mpeg video/ogg video/webm video/quicktime
                  video/x-msvideo video/x-matroska video/3gpp)

  @impl true
  def accept?(content_type), do: content_type in @video_types

  @impl true
  def available?, do: ffmpeg_available?()

  @impl true
  def install_hint do
    "Install ffmpeg: `brew install ffmpeg`, `apt install ffmpeg`, or `nix-shell -p ffmpeg`."
  end

  @impl true
  def preview(input_path, output_path) do
    # -ss 00:00:01: seek to 1s (avoid black frames at t=0 in some codecs)
    # -vframes 1:  extract exactly one frame
    # -f image2:   force image output format
    # -y:          overwrite output without asking
    args = [
      "-i",
      input_path,
      "-ss",
      "00:00:01",
      "-vframes",
      "1",
      "-f",
      "image2",
      "-y",
      output_path
    ]

    try do
      System.cmd(ffmpeg_cmd(), args, stderr_to_stdout: true)

      if File.exists?(output_path) do
        :ok
      else
        # Video shorter than 1s — retry from the beginning
        args0 = ["-i", input_path, "-vframes", "1", "-f", "image2", "-y", output_path]

        case System.cmd(ffmpeg_cmd(), args0, stderr_to_stdout: true) do
          {_, 0} when not is_nil(output_path) ->
            if File.exists?(output_path), do: :ok, else: {:error, "ffmpeg produced no output"}

          {out, code} ->
            {:error, "ffmpeg exited with code #{code}: #{out}"}
        end
      end
    rescue
      ErlangError -> {:error, "ffmpeg not found"}
    end
  end

  defp ffmpeg_available? do
    case Application.get_env(:attached, :ffmpeg, []) |> Keyword.get(:bin) do
      nil -> not is_nil(System.find_executable("ffmpeg"))
      path -> File.exists?(path)
    end
  end

  defp ffmpeg_cmd do
    Application.get_env(:attached, :ffmpeg, [])
    |> Keyword.get(:bin, "ffmpeg")
  end
end
