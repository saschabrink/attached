defmodule Attached.Originals.PurgeWorker do
  @moduledoc """
  Oban worker that asynchronously purges an original and its file from storage.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl true
  def perform(%Oban.Job{args: %{"original_id" => original_id}}) do
    Attached.Originals.purge!(original_id)
  end
end
