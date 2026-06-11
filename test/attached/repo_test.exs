defmodule Attached.RepoTest do
  # Mutates global app env (:attached, :repo) — must not interleave.
  use ExUnit.Case, async: false

  describe "current/0" do
    test "returns the statically configured repo" do
      assert Attached.Repo.current() == Attached.TestRepo
    end

    test "resolves a {mod, fun} tuple" do
      swap_repo_config({__MODULE__, :dynamic_repo})
      assert Attached.Repo.current() == Attached.TestRepo
    end

    test "resolves a 0-arity capture" do
      swap_repo_config(&__MODULE__.dynamic_repo/0)
      assert Attached.Repo.current() == Attached.TestRepo
    end
  end

  describe "current/0 without explicit :repo config (inference)" do
    test "falls back to the single :ecto_repos entry" do
      # Test env configures `:attached, ecto_repos: [Attached.TestRepo]` —
      # the only entry across loaded applications.
      swap_repo_config(nil)
      assert Attached.Repo.current() == Attached.TestRepo
    end

    test "raises when several repos are found instead of picking one" do
      swap_repo_config(nil)

      # :logger is certainly loaded; piggyback a second :ecto_repos entry.
      Application.put_env(:logger, :ecto_repos, [Attached.RepoTest.OtherRepo])
      on_exit(fn -> Application.delete_env(:logger, :ecto_repos) end)

      assert_raise ArgumentError, ~r/Multiple Ecto repos found/, fn ->
        Attached.Repo.current()
      end
    end

    test "duplicate entries across applications still count as one repo" do
      swap_repo_config(nil)

      Application.put_env(:logger, :ecto_repos, [Attached.TestRepo])
      on_exit(fn -> Application.delete_env(:logger, :ecto_repos) end)

      assert Attached.Repo.current() == Attached.TestRepo
    end
  end

  def dynamic_repo, do: Attached.TestRepo

  defp swap_repo_config(value) do
    previous = Application.get_env(:attached, :repo)

    if is_nil(value) do
      Application.delete_env(:attached, :repo)
    else
      Application.put_env(:attached, :repo, value)
    end

    on_exit(fn -> Application.put_env(:attached, :repo, previous) end)
  end
end
