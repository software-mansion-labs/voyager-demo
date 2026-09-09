defmodule Station.Freighter do
  @moduledoc """
  A robot visitor. Simulated load, shaped like a person.

  A freighter does exactly what a ship does - holds a hold of containers in its
  state, sends them to `Station.Warehouse` one message at a time, takes on a
  fresh load when it runs dry - only with a timer where the thumb would be. It
  is what keeps the television and the warehouse alive when the aisle is empty,
  and ops turns the fleet up or down with the crowd (`Station.OpsPanel.set_traffic/1`).

  Three honest differences from a visitor. Its cargo never reaches the
  leaderboard: a booth where the robots outscore the humans has no board worth
  finding your own name on. Its pace is a slow, steady tap, so one freighter is
  a heartbeat and sixteen are a rush hour. And it does not divide the
  inspection cost the way visitors do - see `Station.Cargo.effective_rounds/1` -
  which is what makes the count the load.
  """

  use GenServer, restart: :temporary

  alias Station.Cargo
  alias Station.FreighterLine
  alias Station.Warehouse

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "The published snapshot, same shape as a ship's. No messages sent."
  @spec status(atom()) :: map() | {:error, :gone}
  def status(name) do
    with pid when is_pid(pid) <- Process.whereis(name),
         [{^name, snapshot}] <- :ets.lookup(FreighterLine.status_table(), name),
         info when is_list(info) <- Process.info(pid, [:message_queue_len, :memory]) do
      snapshot
      |> Map.put(:queue, info[:message_queue_len])
      |> Map.put(:memory, info[:memory])
    else
      _ -> {:error, :gone}
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, :low)

    name = Keyword.fetch!(opts, :name)
    cargo_type = Keyword.get_lazy(opts, :cargo_type, fn -> Enum.random(Cargo.types()) end)

    state = %{
      name: name,
      cargo_type: cargo_type,
      hold: Cargo.build_hold(cargo_type),
      hold_count: Cargo.hold_size(),
      hold_size: Cargo.hold_size(),
      delivered: 0,
      refills: 0,
      docked_at: System.system_time(:second),
      # Order of arrival, node-wide and never equal: the television hands out
      # berths by it, and a berth must not move when a clock does.
      berth: :erlang.unique_integer([:monotonic, :positive])
    }

    publish(state)
    schedule(state)

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{hold: []} = state) do
    state = %{
      state
      | hold: Cargo.build_hold(state.cargo_type),
        hold_count: state.hold_size,
        refills: state.refills + 1
    }

    publish(state)
    schedule(state)
    {:noreply, state}
  end

  def handle_info(:tick, %{hold: [container | rest]} = state) do
    Warehouse.accept(nil, container)

    state = %{
      state
      | hold: rest,
        hold_count: state.hold_count - 1,
        delivered: state.delivered + 1
    }

    publish(state)
    schedule(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :ets.delete(FreighterLine.status_table(), state.name)
    :ok
  end

  # An empty hold pauses before the refill, the way a visitor looks up at the
  # screen before pressing TAKE ON CARGO. Everything else is one container per
  # tick, jittered so a fleet does not fire in lockstep.
  defp schedule(%{hold: []}) do
    Process.send_after(self(), :tick, Application.fetch_env!(:station, :freighter_resupply_ms))
  end

  defp schedule(_state) do
    interval = Application.fetch_env!(:station, :freighter_interval_ms)
    Process.send_after(self(), :tick, div(interval, 2) + :rand.uniform(max(interval, 1)))
  end

  defp publish(state) do
    snapshot = %{
      name: state.name,
      slug: Atom.to_string(state.name),
      cargo_type: state.cargo_type,
      hold: state.hold_count,
      hold_size: state.hold_size,
      delivered: state.delivered,
      refills: state.refills,
      pid: inspect(self()),
      docked_at: state.docked_at,
      berth: state.berth,
      freighter?: true
    }

    :ets.insert(FreighterLine.status_table(), {state.name, snapshot})
  end
end
