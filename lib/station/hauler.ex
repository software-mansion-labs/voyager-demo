defmodule Station.Hauler do
  @moduledoc """
  A robot taking cargo back off the station.

  Every pickup is another message into the same warehouse process, and the
  cargo really is copied out to the hauler before it is dropped - which is why
  dispatching more haulers makes the warehouse memory fall rather than just
  making a number go down.
  """

  use GenServer, restart: :temporary

  alias Station.Warehouse

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    Process.flag(:priority, :low)
    schedule()
    {:ok, %{hauled: 0}}
  end

  @impl true
  def handle_info(:collect, state) do
    Warehouse.collect(self(), batch())
    schedule()
    {:noreply, state}
  end

  def handle_info({:cargo_collected, containers}, state) do
    # Off the station and out of the system. The whole point is that this term
    # stops being reachable, so the warehouse's memory is genuinely released.
    {:noreply, %{state | hauled: state.hauled + length(containers)}}
  end

  defp schedule do
    interval = Application.fetch_env!(:station, :hauler_interval_ms)
    Process.send_after(self(), :collect, interval + :rand.uniform(interval))
  end

  defp batch, do: Application.fetch_env!(:station, :hauler_batch)
end
