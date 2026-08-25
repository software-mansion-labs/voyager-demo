defmodule Station.TrafficControl do
  @moduledoc """
  The automatic fleet: the station never sits at zero.

  A node idling at nothing and a node suddenly doing something is a bad
  contrast. A station humming along at a quarter of its schedulers and climbing
  to ninety percent when a crowd arrives reads from the other end of the aisle,
  and it means the booth demos fine at eight in the morning with nobody there.

  It also plants the classic problem: there are many producers and deliberately
  too few consumers, so warehouse memory creeps upward on a long trend until
  ops dispatches more haulers.
  """

  use Supervisor

  @type level :: :quiet | :normal | :rush_hour

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      Station.FreighterLine,
      Station.HaulerLine,
      Station.Dispatcher
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec levels() :: %{level() => map()}
  def levels, do: Application.fetch_env!(:station, :traffic_levels)

  @spec set_level(level()) :: :ok
  def set_level(level), do: Station.Dispatcher.set_level(level)

  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor), do: Station.Dispatcher.set_hauler_boost(factor)
end
