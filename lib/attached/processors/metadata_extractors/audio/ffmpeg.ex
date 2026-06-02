defmodule Attached.Processors.MetadataExtractors.Audio.FFmpeg do
  @moduledoc """
  Extracts duration and bit_rate from audio files using `ffprobe`
  (ships with ffmpeg).
  """

  @behaviour Attached.Processors.MetadataExtractors.Behaviour

  @audio_types ~w(audio/mpeg audio/ogg audio/wav audio/flac audio/aac
                  audio/mp4 audio/webm audio/x-m4a)

  @impl true
  def accept?(content_type), do: content_type in @audio_types

  @impl true
  def available?, do: not is_nil(System.find_executable(ffprobe_cmd()))

  @impl true
  def install_hint do
    "Install ffmpeg: `brew install ffmpeg`, `apt install ffmpeg`, or `nix-shell -p ffmpeg`. The `ffprobe` CLI ships with ffmpeg."
  end

  @impl true
  def metadata(input_path) do
    args = ~w(-print_format json -show_format -v error) ++ [input_path]

    try do
      case System.cmd(ffprobe_cmd(), args, stderr_to_stdout: true) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, %{"format" => fmt}} ->
              %{
                duration: parse_float(fmt["duration"]),
                bit_rate: parse_integer(fmt["bit_rate"])
              }
              |> Enum.reject(fn {_, v} -> is_nil(v) end)
              |> Map.new()

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    rescue
      ErlangError -> %{}
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(s) do
    case Float.parse(to_string(s)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(s) do
    case Integer.parse(to_string(s)) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp ffprobe_cmd do
    Application.get_env(:attached, :ffmpeg, [])
    |> Keyword.get(:ffprobe_bin, "ffprobe")
  end
end
