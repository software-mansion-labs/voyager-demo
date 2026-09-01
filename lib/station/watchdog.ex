defmodule Station.Watchdog do
  @moduledoc """
  Samples the station's vital signs once, so nothing else has to.

  `Process.info/2` against a congested process is not free, and the warehouse is
  congested by design. One sampler writes the numbers into `Station.Metrics`,
  every phone, dashboard and rate limiter reads them from there.

  It is also the alarm: if the station is drowning it says so on every screen.
  There is no background traffic left to shed - all load is visitors - so the
  fix is the room's, or the ops panel's.
  """

  use GenServer

  alias Station.Events
  alias Station.Metrics
  alias Station.Warehouse

  @interval 500
  @recovered_after 6

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{panicking?: false, calm_ticks: 0}}
  end

  @impl true
  def handle_info(:sample, state) do
    sample()
    schedule()
    {:noreply, guard(state)}
  end

  defp sample do
    case Process.whereis(Warehouse) do
      nil ->
        Metrics.put(:queue, 0)
        Metrics.put(:warehouse_memory, 0)

      pid ->
        info = Process.info(pid, [:message_queue_len, :memory, :reductions]) || []
        Metrics.put(:queue, Keyword.get(info, :message_queue_len, 0))
        Metrics.put(:warehouse_memory, Keyword.get(info, :memory, 0))
        Metrics.put(:warehouse_reductions, Keyword.get(info, :reductions, 0))
    end

    Metrics.put(:run_queue, :erlang.statistics(:total_run_queue_lengths))
    Metrics.put(:process_count, :erlang.system_info(:process_count))
    Metrics.put(:atom_count, :erlang.system_info(:atom_count))
  end

  defp guard(state) do
    limits = Application.fetch_env!(:station, :watchdog)

    drowning? =
      Metrics.get(:queue) > limits[:max_queue] or Metrics.get(:run_queue) > limits[:max_run_queue]

    cond do
      drowning? and not state.panicking? ->
        Events.emit(:watchdog, "WATCHDOG - STATION OVERLOADED", :error)

        %{state | panicking?: true, calm_ticks: 0}

      state.panicking? and not drowning? and state.calm_ticks >= @recovered_after ->
        Events.emit(:watchdog, "WATCHDOG - STATION RECOVERED", :info)
        %{state | panicking?: false, calm_ticks: 0}

      state.panicking? and not drowning? ->
        %{state | calm_ticks: state.calm_ticks + 1}

      true ->
        %{state | calm_ticks: 0}
    end
  end

  defp schedule, do: Process.send_after(self(), :sample, @interval)
end
