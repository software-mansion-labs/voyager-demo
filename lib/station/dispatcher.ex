defmodule Station.Dispatcher do
  @moduledoc """
  Keeps both lines of the fleet staffed.

  Haulers are the drain: they take cargo back off the station, which is what
  lets warehouse memory fall while somebody watches. Freighters are the
  simulated visitors ops turns on when the aisle is quiet. This process notices
  gaps in either crew and sends replacements, and applies whatever ops last
  asked for - the hauler boost and the freighter count.
  """

  use GenServer

  alias Station.DockingBay
  alias Station.Freighter
  alias Station.FreighterLine
  alias Station.Hauler
  alias Station.HaulerLine
  alias Station.OpsPanel

  @tick 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Calls, not casts: when ops presses the switch the crew is on duty by the
  # time the shell prompt comes back, and a test asking for zero gets zero.
  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor), do: GenServer.call(__MODULE__, {:set_hauler_boost, factor})

  @spec set_freighters(non_neg_integer()) :: :ok
  def set_freighters(count), do: GenServer.call(__MODULE__, {:set_freighters, count})

  @doc "Re-staffs both lines now instead of on the next tick."
  @spec reconcile() :: :ok
  def reconcile, do: GenServer.call(__MODULE__, :reconcile)

  @doc "Sends one freighter home now, for a visitor who is docking this instant."
  @spec make_room() :: :ok
  def make_room, do: GenServer.call(__MODULE__, :make_room)

  @doc "Current crew sizes, for the dashboards."
  @spec fleet() :: %{haulers: non_neg_integer(), freighters: non_neg_integer()}
  def fleet do
    %{
      haulers: DynamicSupervisor.count_children(HaulerLine).active,
      freighters: FreighterLine.count()
    }
  end

  @impl true
  def init(_opts) do
    send(self(), :tick)
    {:ok, %{boost: OpsPanel.hauler_boost(), freighters: OpsPanel.freighters()}}
  end

  @impl true
  def handle_call({:set_hauler_boost, factor}, _from, state) do
    state = %{state | boost: factor}
    reconcile(state)
    {:reply, :ok, state}
  end

  def handle_call({:set_freighters, count}, _from, state) do
    state = %{state | freighters: count}
    reconcile(state)
    {:reply, :ok, state}
  end

  def handle_call(:reconcile, _from, state) do
    reconcile(state)
    {:reply, :ok, state}
  end

  def handle_call(:make_room, _from, state) do
    staff(FreighterLine, Freighter, "freighter", max(FreighterLine.count() - 1, 0))
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    reconcile(state)
    Process.send_after(self(), :tick, @tick)
    {:noreply, state}
  end

  defp reconcile(state) do
    staff(HaulerLine, Hauler, "hauler", haulers(state))
    staff(FreighterLine, Freighter, "freighter", freighters(state))
  end

  # Freighters fill whatever berths the visitors leave, never more - a ship is
  # a ship on the screen and the cap is the cap. With yield on, people also take
  # the freighters' places one for one: the tick sees a visitor dock and sends
  # a freighter home within the second, and brings one back when they leave.
  defp freighters(state) do
    visitors = DockingBay.count()
    room = DockingBay.capacity() - visitors

    wanted =
      if OpsPanel.yield_to_visitors?(),
        do: state.freighters - visitors,
        else: state.freighters

    wanted |> min(room) |> max(0)
  end

  # Brings a line to its target size: sends the highest numbers home when
  # over, fills the lowest free numbers when under - so `freighter_03` really
  # is the third one, and turning traffic down keeps `_01` on the screen.
  defp staff(line, worker, label, target) do
    indexed = indexed_children(line)
    excess = length(indexed) - target

    if excess > 0 do
      indexed
      |> Enum.sort_by(fn {index, _pid} -> -index end)
      |> Enum.take(excess)
      |> Enum.each(fn {_index, pid} -> DynamicSupervisor.terminate_child(line, pid) end)
    end

    taken = MapSet.new(indexed_children(line), fn {index, _pid} -> index end)
    missing = target - MapSet.size(taken)

    if missing > 0 do
      1..99
      |> Enum.reject(&MapSet.member?(taken, &1))
      |> Enum.take(missing)
      |> Enum.each(fn index ->
        DynamicSupervisor.start_child(line, {worker, name: worker_name(label, index)})
      end)
    end
  end

  defp indexed_children(line) do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(line),
        {:registered_name, name} <- [Process.info(pid, :registered_name)],
        is_atom(name),
        [_, digits] <- [String.split(Atom.to_string(name), "_")] do
      {String.to_integer(digits), pid}
    end
  end

  defp haulers(state), do: Application.fetch_env!(:station, :haulers) * state.boost

  # Ninety nine names per line, minted once each: the pool is the cap.
  defp worker_name(label, index),
    do: :"#{label}_#{String.pad_leading(to_string(index), 2, "0")}"
end
