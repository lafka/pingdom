defmodule Pingdom.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    metrics = Application.get_env :pingdom, :metrics, %{}
    workers = Enum.map metrics, fn({k, {test, _metric, interval, args}}) ->
      {:"#{k}", {Pingdom.Tests, :start_link, [k, test, interval, args]}, :permanent, 5000, :worker, [Pingdom.Tests]}
    end

    children = [
      {:storage, {Pingdom.Storage, :start_link, []}, :permanent, 5000, :worker, [Pingdom.Storage]},
      {:incidents, {Pingdom.Incidents, :start_link, []}, :permanent, 5000, :worker, [Pingdom.Incidents]}
      | workers
    ]

    opts = [strategy: :one_for_one, name: Pingdom.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
