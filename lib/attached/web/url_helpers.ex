defmodule Attached.Web.UrlHelpers do
  @moduledoc """
  Template helpers for rendering attachment URLs.

  ## Usage

  Import in your web module:

      defmodule MyAppWeb do
        def html_helpers do
          quote do
            import Attached.Web.UrlHelpers
          end
        end
      end

  Then in templates:

      <img src={storage_url(@user, :avatar)} />
      <img src={storage_url(@user, :avatar, :thumb)} />
  """

  @doc """
  Returns the URL for an attachment, or `nil` if nothing is attached.

      storage_url(user, :avatar)
      storage_url(user, :avatar, :thumb)
  """
  def storage_url(record, field, variant \\ nil) do
    Attached.url(record, field, variant)
  end
end
