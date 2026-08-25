defmodule Station.Dispatcher do
  @moduledoc """
  Keeps both lines staffed.

  Freighters are temporary on purpose: each one runs a delivery trip and then
  leaves, so the fleet churns and the collapsed branches in Voyager keep
  ticking instead of standing still. This process notices the gaps and sends
  replacements.
  """

  use GenServer

  alias Station.Freighter
  alias Station.FreighterLine
  alias Station.Hauler
  alias Station.HaulerLine
  alias Station.OpsPanel
  alias Station.TrafficControl

  @tick 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec set_level(TrafficControl.level()) :: :ok
  def set_level(level), do: GenServer.cast(__MODULE__, {:set_level, level})

  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor), do: GenServer.cast(__MODULE__, {:set_hauler_boost, factor})

  @doc "Current fleet size, for the dashboards."
  @spec fleet() :: %{freighters: non_neg_integer(), haulers: non_neg_integer()}
  def fleet do
    %{
      freighters: DynamicSupervisor.count_children(FreighterLine).active,
      haulers: DynamicSupervisor.count_children(HaulerLine).active
    }
  end

  @impl true
  def init(_opts) do
    state = %{level: OpsPanel.traffic(), boost: OpsPanel.hauler_boost()}
    send(self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_cast({:set_level, level}, state), do: {:noreply, restaff(%{state | level: level})}

  def handle_cast({:set_hauler_boost, factor}, state) do
    {:noreply, restaff(%{state | boost: factor})}
  end

  @impl true
  def handle_info(:tick, state) do
    top_up(state)
    Process.send_after(self(), :tick, @tick)
    {:noreply, state}
  end

  defp restaff(state) do
    trim(FreighterLine, freighter_target(state))
    trim(HaulerLine, hauler_target(state))
    top_up(state)
    state
  end

  defp top_up(state) do
    staff(FreighterLine, Freighter, "freighter", freighter_target(state), interval(state))
    staff(HaulerLine, Hauler, "hauler", hauler_target(state), nil)
  end

  defp staff(line, worker, prefix, target, interval) do
    taken = registered_indexes(line)
    missing = target - MapSet.size(taken)

    if missing > 0 do
      1..99
      |> Enum.reject(&MapSet.member?(taken, &1))
      |> Enum.take(missing)
      |> Enum.each(fn index ->
        opts = [name: worker_name(prefix, index)]
        opts = if interval, do: Keyword.put(opts, :interval_ms, interval), else: opts
        DynamicSupervisor.start_child(line, {worker, opts})
      end)
    end
  end

  defp trim(line, target) do
    children = DynamicSupervisor.which_children(line)
    excess = length(children) - target

    if excess > 0 do
      children
      |> Enum.take(excess)
      |> Enum.each(fn {_, pid, _, _} -> DynamicSupervisor.terminate_child(line, pid) end)
    end
  end

  defp registered_indexes(line) do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(line),
        {:registered_name, name} <- [Process.info(pid, :registered_name)],
        is_atom(name),
        [_, digits] <- [String.split(Atom.to_string(name), "_")],
        into: MapSet.new() do
      String.to_integer(digits)
    end
  end

  defp freighter_target(state), do: level_config(state).freighters

  defp hauler_target(state) do
    Application.fetch_env!(:station, :haulers) * state.boost
  end

  defp interval(state), do: level_config(state).interval_ms

  defp level_config(state) do
    TrafficControl.levels() |> Map.fetch!(state.level)
  end

  defp worker_name(prefix, index) do
    :"#{prefix}_#{String.pad_leading(to_string(index), 2, "0")}"
  end
end
