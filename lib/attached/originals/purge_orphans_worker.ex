defmodule Attached.Originals.PurgeOrphansWorker do
  @moduledoc """
  Oban worker that finds and purges orphaned originals.

  An original is orphaned when no row in its `owner_table` references it
  via the `owner_field` column. The owner can be the schema declaring
  the attachment (e.g. `owner_table = "articles"`,
  `owner_field = "header_image_attached_original_id"`) or a user-defined
  join schema (e.g. `owner_table = "article_images_attachments"`,
  `owner_field = "attached_original_id"`).

  Variants are not part of this sweep — they live in `attached_variants`
  and are cleaned up via the `original_id` FK (`on_delete: :delete_all`)
  when their parent original is purged.

  ## Grace period

  Only orphans older than the configured grace period are purged, so
  originals created ahead of their attachment (e.g. direct uploads whose
  form hasn't been submitted yet) survive the sweep while in flight:

      config :attached, orphan_grace_period: 172_800  # seconds (48 hours), the default

  Set `0` to purge orphans regardless of age.

  Schedule as a cron job:

      config :my_app, Oban,
        plugins: [
          {Oban.Plugins.Cron, crontab: [
            {"0 3 * * *", Attached.Originals.PurgeOrphansWorker}
          ]}
        ]
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Attached.Originals
  alias Attached.Originals.Scopes

  @impl true
  def perform(%Oban.Job{}) do
    Enum.each(Originals.list_owner_groups(), fn %{owner_table: owner_table, owner_field: owner_field} ->
      Originals.list(query: &Scopes.purgeable(&1, owner_table, owner_field))
      |> Enum.each(&Originals.purge!/1)
    end)

    :ok
  end
end
