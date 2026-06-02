defmodule Attached.Repo do
  @moduledoc """
  Resolves the Ecto repo used by Attached.

  Normally an internal concern — Attached's own context modules call
  `current/0` to pick up the host app's repo. Exposed publicly for the
  rare case where a caller needs the same resolution logic (e.g. a
  dashboard or maintenance script).

  ## Configuration

  Static repo — the common case:

      config :attached, :repo, MyApp.Repo

  Dynamic resolution — for multi-tenant apps with per-request repos:

      # mod/fun
      config :attached, :repo, {MyApp.Tenant, :current_repo}

      # capture
      config :attached, :repo, &MyApp.Tenant.current_repo/0

  Without explicit config, Attached falls back to the first `:ecto_repos`
  entry of any loaded application — convenient for single-repo apps where
  you haven't wired Attached up yet.

  ## Why no per-call `:repo` option?

  Previous versions accepted `repo: MyApp.Repo` on every public function.
  That pushed repo plumbing into every caller for the sake of a feature
  (dynamic repos) most apps never use. The callback config above covers
  the dynamic case without polluting the API.
  """

  @doc """
  Returns the configured repo, raising if none can be resolved.
  """
  def current do
    case Application.get_env(:attached, :repo) do
      nil -> infer() || raise_missing()
      mod when is_atom(mod) -> mod
      {mod, fun} -> apply(mod, fun, [])
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp infer do
    :application.loaded_applications()
    |> Enum.find_value(fn {app, _, _} ->
      case Application.get_env(app, :ecto_repos) do
        [repo | _] -> repo
        _ -> nil
      end
    end)
  end

  defp raise_missing do
    raise """
    Could not determine the Ecto repo. Configure it:

        config :attached, :repo, MyApp.Repo

    For dynamic repos, pass a {mod, fun} tuple or a 0-arity function:

        config :attached, :repo, {MyApp.Tenant, :current_repo}
        config :attached, :repo, &MyApp.Tenant.current_repo/0
    """
  end
end
