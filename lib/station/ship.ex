defmodule Station.Ship do
  @moduledoc """
  One visitor, as a named process in the station's supervision tree.

  The whole trick of the demo is that there is nothing behind this. A ship is a
  GenServer holding a hold full of containers in its state. Pressing TRANSFER
  casts one message to this process; loading a container onto the ramp takes a
  moment (`:ship_load_ms`), and only then does exactly one message go to
  `Station.Warehouse`.

  The cast is the point. A thumb faster than the loading ramp piles messages up
  in *this ship's* mailbox, so the visitor's own process grows a queue they can
  find in Voyager - the same lesson as the warehouse, one level closer to home.
  It is also the rate limit: a ship ships at ramp speed no matter how fast
  anyone taps, and the cockpit refuses new presses once the mailbox is deep.

  Nothing reads this process with a call. A GenServer sleeping on its ramp would
  make every caller queue behind the cargo, so the ship publishes its state to
  an ETS table after every event and `status/1` reads that - plus the queue and
  memory, which `Process.info/2` reads from outside for free.
  """

  use GenServer, restart: :temporary

  alias Station.Cargo
  alias Station.DockingBay
  alias Station.Events
  alias Station.Metrics
  alias Station.ShipNames
  alias Station.Warehouse

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "One press. One message into this ship's own mailbox."
  @spec transfer(atom()) :: :ok | {:error, :gone}
  def transfer(name) do
    case Process.whereis(name) do
      nil -> {:error, :gone}
      pid -> GenServer.cast(pid, :transfer)
    end
  end

  @doc "How deep this ship's own mailbox is. Read from outside, never asked."
  @spec queue_len(atom()) :: non_neg_integer()
  def queue_len(name) do
    with pid when is_pid(pid) <- Process.whereis(name),
         {:message_queue_len, queue} <- Process.info(pid, :message_queue_len) do
      queue
    else
      _ -> 0
    end
  end

  @doc "The published snapshot plus the live queue and memory. No messages sent."
  @spec status(atom()) :: map() | {:error, :gone}
  def status(name) do
    with pid when is_pid(pid) <- Process.whereis(name),
         [{^name, snapshot}] <- :ets.lookup(DockingBay.status_table(), name),
         info when is_list(info) <- Process.info(pid, [:message_queue_len, :memory]) do
      snapshot
      |> Map.put(:queue, info[:message_queue_len])
      |> Map.put(:memory, info[:memory])
    else
      _ -> {:error, :gone}
    end
  end

  @spec undock(atom()) :: :ok
  def undock(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    name = Keyword.fetch!(opts, :name)
    cargo_type = Keyword.fetch!(opts, :cargo_type)

    state = %{
      name: name,
      slug: ShipNames.to_slug(name),
      cargo_type: cargo_type,
      hold: Cargo.build_hold(cargo_type),
      hold_count: Cargo.hold_size(),
      hold_size: Cargo.hold_size(),
      delivered: 0,
      refills: 0,
      last_press: now_ms(),
      docked_at: System.system_time(:second)
    }

    Metrics.add(:ships_docked, 1)
    Events.emit(:dock, "#{name} DOCKED - #{String.upcase(cargo_type)}")
    publish(state)

    {:ok, state, ttl()}
  end

  @impl true
  def handle_cast(:transfer, state) do
    state = %{state | last_press: now_ms()}

    # The ramp. This sleep is what turns a fast thumb into a visible queue on
    # this process - and it costs no scheduler anything, unlike real work here
    # would with twenty five ships aboard.
    load_ms() > 0 && Process.sleep(load_ms())

    state = ship_one(state)
    {:noreply, state, remaining(state)}
  end

  @impl true
  def handle_info(:timeout, state) do
    Events.emit(:undock, "#{state.name} DRIFTED OFF - IDLE TIMEOUT")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state, remaining(state)}

  @impl true
  def terminate(_reason, state) do
    :ets.delete(DockingBay.status_table(), state.name)
    Metrics.add(:ships_undocked, 1)
    Events.emit(:undock, "#{state.name} UNDOCKED - #{state.delivered} CONTAINERS DELIVERED")
    :ok
  end

  defp ship_one(%{hold: [container | rest]} = state) do
    Warehouse.accept(state.slug, container)

    state = %{
      state
      | hold: rest,
        hold_count: state.hold_count - 1,
        delivered: state.delivered + 1
    }

    state = refill_if_empty(state)
    publish(state)
    state
  end

  defp refill_if_empty(%{hold: []} = state) do
    Events.emit(
      :refill,
      "#{state.name} TOOK ON A FRESH LOAD OF #{String.upcase(state.cargo_type)}"
    )

    %{
      state
      | hold: Cargo.build_hold(state.cargo_type),
        hold_count: state.hold_size,
        refills: state.refills + 1
    }
  end

  defp refill_if_empty(state), do: state

  defp publish(state) do
    snapshot = %{
      name: state.name,
      slug: state.slug,
      cargo_type: state.cargo_type,
      hold: state.hold_count,
      hold_size: state.hold_size,
      delivered: state.delivered,
      refills: state.refills,
      pid: inspect(self()),
      docked_at: state.docked_at
    }

    :ets.insert(DockingBay.status_table(), {state.name, snapshot})
  end

  # Idle means nobody is pressing the button, not that nobody is looking at the
  # page - and since status/1 stopped sending messages entirely, only presses
  # and this timeout ever reach the mailbox's clock.
  defp remaining(state), do: max(ttl() - (now_ms() - state.last_press), 0)

  defp ttl, do: Application.fetch_env!(:station, :ship_ttl_ms)

  defp load_ms, do: Application.fetch_env!(:station, :ship_load_ms)

  defp now_ms, do: System.monotonic_time(:millisecond)
end
