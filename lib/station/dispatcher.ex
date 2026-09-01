defmodule Station.Dispatcher do
  @moduledoc """
  Keeps the hauler line staffed.

  Haulers are the drain: they take cargo back off the station, which is what
  lets warehouse memory fall while somebody watches. This process notices gaps
  in the crew and sends replacements, and applies the ops boost.
  """

  use GenServer

  alias Station.Hauler
  alias Station.HaulerLine
  alias Station.OpsPanel

  @tick 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor), do: GenServer.cast(__MODULE__, {:set_hauler_boost, factor})

  @doc "Current crew size, for the dashboards."
  @spec fleet() :: %{haulers: non_neg_integer()}
  def fleet do
    %{haulers: DynamicSupervisor.count_children(HaulerLine).active}
  end

  @impl true
  def init(_opts) do
    send(self(), :tick)
    {:ok, %{boost: OpsPanel.hauler_boost()}}
  end

  @impl true
  def handle_cast({:set_hauler_boost, factor}, state) do
    state = %{state | boost: factor}
    trim(target(state))
    top_up(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    top_up(state)
    Process.send_after(self(), :tick, @tick)
    {:noreply, state}
  end

  defp top_up(state) do
    taken = registered_indexes()
    missing = target(state) - MapSet.size(taken)

    if missing > 0 do
      1..99
      |> Enum.reject(&MapSet.member?(taken, &1))
      |> Enum.take(missing)
      |> Enum.each(fn index ->
        DynamicSupervisor.start_child(HaulerLine, {Hauler, name: worker_name(index)})
      end)
    end
  end

  defp trim(target) do
    children = DynamicSupervisor.which_children(HaulerLine)
    excess = length(children) - target

    if excess > 0 do
      children
      |> Enum.take(excess)
      |> Enum.each(fn {_, pid, _, _} -> DynamicSupervisor.terminate_child(HaulerLine, pid) end)
    end
  end

  defp registered_indexes do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(HaulerLine),
        {:registered_name, name} <- [Process.info(pid, :registered_name)],
        is_atom(name),
        [_, digits] <- [String.split(Atom.to_string(name), "_")],
        into: MapSet.new() do
      String.to_integer(digits)
    end
  end

  defp target(state), do: Application.fetch_env!(:station, :haulers) * state.boost

  defp worker_name(index), do: :"hauler_#{String.pad_leading(to_string(index), 2, "0")}"
end
