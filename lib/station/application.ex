defmodule Station.Application do
  @moduledoc """
  One application, one supervision tree, one system.

  The child order is the station's boot order and it matters: settings and the
  leaderboard first, then the inspection crew the warehouse looks for on start,
  then the warehouse everything else talks to, then the ships and the fleet
  that talk to it.

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
      Station.Leaderboard,
      Station.InspectionCrew,
      Station.Warehouse,
      Station.DockingBay,
      Station.TrafficControl,
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
