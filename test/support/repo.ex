defmodule Attached.TestRepo do
  use Ecto.Repo,
    otp_app: :attached,
    adapter: Ecto.Adapters.SQLite3
end
