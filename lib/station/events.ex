defmodule Station.Events do
  @moduledoc """
  The station's event log, broadcast over PubSub.

  Discrete things only - a ship docking, the warehouse dropping cargo, ops
  flipping a switch. Continuous metrics are polled from `Station.Metrics` and
  `Process.info/2` instead, so a busy warehouse never has to announce itself.
  """

  @topic "station:events"

  @type event :: %{
          kind: atom(),
          text: String.t(),
          level: :info | :warning | :error,
          at: integer()
        }

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Station.PubSub, @topic)

  @spec topic() :: String.t()
  def topic, do: @topic

  @spec emit(atom(), String.t(), :info | :warning | :error) :: :ok
  def emit(kind, text, level \\ :info) do
    event = %{kind: kind, text: text, level: level, at: System.system_time(:millisecond)}
    Phoenix.PubSub.broadcast(Station.PubSub, @topic, {:station_event, event})
  end
end
