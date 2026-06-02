defmodule Attached.Originals.ExtractMetadataWorker do
  @moduledoc """
  Oban worker that extracts metadata from an original and stores it.

  Enqueued automatically after original creation. Finds the first extractor
  that accepts the original's content type, downloads the original to a tmp file,
  runs the extractor, and merges the result into `original.metadata`.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Attached.Originals
  alias Attached.Processors.MetadataExtractors
  alias Attached.StorageBackends

  @impl true
  def perform(%Oban.Job{args: %{"original_id" => original_id}}) do
    original = Originals.get!(original_id)

    case MetadataExtractors.find_for(original.content_type) do
      nil ->
        :ok

      extractor ->
        {:ok, data} = StorageBackends.download(original.key)
        ext = original.filename |> Path.extname() |> String.downcase()
        tmp = Path.join(System.tmp_dir!(), "attached-extract-#{original.id}#{ext}")

        try do
          File.write!(tmp, data)
          Originals.update_metadata!(original, extractor.metadata(tmp))
        after
          File.rm(tmp)
        end

        :ok
    end
  end
end
