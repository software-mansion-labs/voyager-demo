defmodule Station.Game do
  @moduledoc """
  The station itself: everything a visitor can see, touch or break.

  One supervisor, so the tree in Voyager separates the two things that are easy
  to confuse from across a room. Under `Station.Game` is the demo - the board,
  the inspectors, the warehouse, the visitors' ships and the fleet. Above it, in
  the application supervisor, is the plumbing that carries the demo to a screen:
  telemetry, PubSub, the ops settings, the watchdog and the endpoint.

  That is also the boundary a visitor is told about: everything in this subtree
  exists because somebody pressed a button, and it can be killed and watched to
  come back without taking the website down with it.

  The child order is the boot order and it matters: the board and the inspection
  crew first, because the warehouse looks for the crew when it starts, then the
  warehouse everything else talks to, then the ships and the fleet that talk to it.
  """

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      Station.Leaderboard,
      Station.InspectionCrew,
      Station.Warehouse,
      Station.DockingBay,
      Station.TrafficControl
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
