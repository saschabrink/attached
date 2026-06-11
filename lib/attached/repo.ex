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

  Without explicit config, Attached falls back to the `:ecto_repos` entry of
  the loaded applications — but only when there is exactly one repo across
  all of them. Convenient for single-repo apps where you haven't wired
  Attached up yet; with several repos (umbrellas, multi-app setups) the
  fallback raises instead of silently picking one, since the order of loaded
  applications is undefined.

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
      nil -> infer()
      mod when is_atom(mod) -> mod
      {mod, fun} -> apply(mod, fun, [])
      fun when is_function(fun, 0) -> fun.()
    end
  end

  # Only one configured repo across all loaded applications is unambiguous.
  # `:application.loaded_applications/0` has no defined order, so "first
  # match" would make multi-repo setups (umbrellas) pick nondeterministically.
  defp infer do
    repos =
      :application.loaded_applications()
      |> Enum.flat_map(fn {app, _, _} -> List.wrap(Application.get_env(app, :ecto_repos, [])) end)
      |> Enum.uniq()

    case repos do
      [repo] ->
        repo

      [] ->
        raise """
        Could not determine the Ecto repo. Configure it:

            config :attached, :repo, MyApp.Repo

        For dynamic repos, pass a {mod, fun} tuple or a 0-arity function:

            config :attached, :repo, {MyApp.Tenant, :current_repo}
            config :attached, :repo, &MyApp.Tenant.current_repo/0
        """

      repos ->
        raise ArgumentError, """
        Multiple Ecto repos found (#{inspect(repos)}) — refusing to pick one
        by application load order. Configure the repo Attached should use:

            config :attached, :repo, #{inspect(hd(repos))}
        """
    end
  end
end
