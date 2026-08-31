defmodule Station.Application do
  @moduledoc """
  One application, one supervision tree, one system.

  Two layers, because they fail for different reasons. This supervisor holds the
  plumbing: telemetry, PubSub, the ops settings the demo reads on start, the
  watchdog and the endpoint. Everything a visitor can see, touch or break lives
  one level down, under `Station.Game`.

  The names below are the names visitors will read off a television, so they
  are chosen to make the tree explain itself without a legend.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Station.Metrics.setup()

    children = [
      StationWeb.Telemetry,
      {Phoenix.PubSub, name: Station.PubSub},
      Station.OpsPanel,
      Station.Game,
      Station.Watchdog,
      StationWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Station.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    StationWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
