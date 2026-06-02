defmodule Attached.Processors.MetadataExtractors.Video.FFmpeg do
  @moduledoc """
  Extracts width, height, duration, angle, display_aspect_ratio, and
  audio/video channel flags from video files using `ffprobe`
  (ships with ffmpeg).
  """

  @behaviour Attached.Processors.MetadataExtractors.Behaviour

  @video_types ~w(video/mp4 video/mpeg video/ogg video/webm video/quicktime
                  video/x-msvideo video/x-matroska video/3gpp)

  @impl true
  def accept?(content_type), do: content_type in @video_types

  @impl true
  def available?, do: not is_nil(System.find_executable(ffprobe_cmd()))

  @impl true
  def install_hint do
    "Install ffmpeg: `brew install ffmpeg`, `apt install ffmpeg`, or `nix-shell -p ffmpeg`. The `ffprobe` CLI ships with ffmpeg."
  end

  @impl true
  def metadata(input_path) do
    case probe(input_path) do
      {:ok, data} -> extract(data)
      :error -> %{}
    end
  end

  defp extract(data) do
    streams = Map.get(data, "streams", [])
    container = Map.get(data, "format", %{})

    video = Enum.find(streams, &(&1["codec_type"] == "video"))
    audio = Enum.find(streams, &(&1["codec_type"] == "audio"))

    angle = rotation_angle(video)
    rotated = angle in [90, 270, -90, -270]

    raw_w = get_float(video, "width")
    raw_h = get_float(video, "height")
    {w, h} = if rotated, do: {raw_h, raw_w}, else: {raw_w, raw_h}

    %{
      width: w,
      height: h,
      duration: get_float(video, "duration") || get_float(container, "duration"),
      angle: if(angle != 0, do: angle),
      display_aspect_ratio: parse_aspect_ratio(video && video["display_aspect_ratio"]),
      audio: not is_nil(audio),
      video: not is_nil(video)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp probe(input_path) do
    args = ~w(-print_format json -show_streams -show_format -v error) ++ [input_path]

    try do
      case System.cmd(ffprobe_cmd(), args, stderr_to_stdout: true) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, data} -> {:ok, data}
            _ -> :error
          end

        _ ->
          :error
      end
    rescue
      ErlangError -> :error
    end
  end

  defp rotation_angle(nil), do: 0

  defp rotation_angle(video_stream) do
    tags = Map.get(video_stream, "tags", %{})
    side_data = Map.get(video_stream, "side_data_list", [])

    cond do
      rotate = tags["rotate"] ->
        String.to_integer(rotate)

      dm = Enum.find(side_data, &(&1["side_data_type"] == "Display Matrix")) ->
        Map.get(dm, "rotation", 0)

      true ->
        0
    end
  end

  defp parse_aspect_ratio(nil), do: nil

  defp parse_aspect_ratio(s) do
    case String.split(s, ":") do
      [n, d] ->
        case {Integer.parse(n), Integer.parse(d)} do
          {{num, _}, {den, _}} when num > 0 -> [num, den]
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_float(nil, _), do: nil

  defp get_float(map, key) do
    case map[key] do
      nil ->
        nil

      val ->
        case Float.parse(to_string(val)) do
          {f, _} -> f
          :error -> nil
        end
    end
  end

  defp ffprobe_cmd do
    Application.get_env(:attached, :ffmpeg, [])
    |> Keyword.get(:ffprobe_bin, "ffprobe")
  end
end
