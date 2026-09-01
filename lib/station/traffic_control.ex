defmodule Station.TrafficControl do
  @moduledoc """
  The outbound side of the station: the hauler crew and its dispatcher.

  There is no inbound fleet. Every container that reaches the warehouse was
  pressed onto it by a visitor, so the queue and the memory on the television
  are the room's own doing - an empty room is a station at zero, which is
  exactly what it claims to be.
  """

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      Station.HaulerLine,
      Station.Dispatcher
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor), do: Station.Dispatcher.set_hauler_boost(factor)
end
