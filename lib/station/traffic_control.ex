defmodule Station.TrafficControl do
  @moduledoc """
  The fleet: the hauler crew, the freighter line and their dispatcher.

  Haulers take cargo off the station. Freighters put it on, standing in for
  visitors when the aisle is empty - and there are none until ops asks, so an
  empty room with traffic off is a station at zero, which is exactly what it
  claims to be.
  """

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      Station.HaulerLine,
      Station.FreighterLine,
      Station.Dispatcher
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor), do: Station.Dispatcher.set_hauler_boost(factor)

  @spec set_freighters(non_neg_integer()) :: :ok
  def set_freighters(count), do: Station.Dispatcher.set_freighters(count)
end
