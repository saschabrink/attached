defmodule Attached.DataCase do
  @moduledoc """
  ExUnit case template for tests that hit the database. Wraps each test in
  an Ecto SQL sandbox so all changes are rolled back after the test.

  Use `async: false` (the default) for SQLite — concurrent sandbox ownership
  is not supported there.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Attached.TestRepo, as: Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Attached.DataCase
    end
  end

  setup tags do
    Attached.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Attached.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Variants.create_variant(%{name: "bad-name"})
      assert "must match ..." in errors_on(changeset).name
      assert %{name: ["must match ..."]} = errors_on(changeset)
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
