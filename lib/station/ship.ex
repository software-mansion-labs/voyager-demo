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

  The cockpit that flies this ship boards it (`board/2`) and the ship monitors
  that process. When the cockpit goes dark and stays dark past
  `:ship_leave_grace_ms`, the ship leaves its notes in `Station.Hangar` and
  undocks - a berth belongs to somebody standing in front of the screen, not to
  a phone in a pocket. The same session scanning again docks it back.
  """

  use GenServer, restart: :temporary

  alias Station.Cargo
  alias Station.DockingBay
  alias Station.Events
  alias Station.Hangar
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
  def transfer(name), do: press(name, :transfer)

  @doc "Takes on a fresh hold. A decision, not an automatism - see handle_cast."
  @spec resupply(atom()) :: :ok | {:error, :gone}
  def resupply(name), do: press(name, :resupply)

  defp press(name, message) do
    case Process.whereis(name) do
      nil -> {:error, :gone}
      pid -> GenServer.cast(pid, message)
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

  @doc "The PubSub topic a ship announces each departed container on."
  @spec topic(String.t()) :: String.t()
  def topic(slug), do: "ship:" <> slug

  @spec undock(atom()) :: :ok
  def undock(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  @doc """
  A cockpit takes the controls. The ship watches this process from now on and
  parks itself once it has been gone for the grace period; a reload or a wifi
  blip that comes back inside it changes nothing.
  """
  @spec board(atom(), pid()) :: :ok | {:error, :gone}
  def board(name, crew) when is_pid(crew), do: press(name, {:board, crew})

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    name = Keyword.fetch!(opts, :name)
    cargo_type = Keyword.fetch!(opts, :cargo_type)
    parked = Keyword.get(opts, :restore)

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
      docked_at: System.system_time(:second),
      # Order of arrival, node-wide and never equal: the television hands out
      # berths by it, and a berth must not move when a clock does.
      berth: :erlang.unique_integer([:monotonic, :positive]),
      # The cockpit flying this ship, as {pid, monitor ref}, and the timer that
      # parks the ship once that cockpit has been dark for long enough.
      crew: nil,
      leaving: nil
    }

    state = if parked, do: restore(state, parked), else: state

    Metrics.add(:ships_docked, 1)

    if parked do
      Events.emit(
        :dock,
        "#{name} DOCKED AGAIN - #{String.upcase(cargo_type)}, #{state.delivered} DELIVERED SO FAR"
      )
    else
      Events.emit(:dock, "#{name} DOCKED - #{String.upcase(cargo_type)}")
    end

    publish(state)

    {:ok, state, ttl()}
  end

  @impl true
  def handle_cast(:transfer, %{hold: []} = state) do
    # Presses queued behind the last container die quietly at the ramp: the
    # hold does not refill itself. An empty ship is a decision waiting for the
    # visitor - the button on the phone turns into TAKE ON CARGO.
    {:noreply, %{state | last_press: now_ms()}, remaining(state)}
  end

  def handle_cast(:transfer, state) do
    state = %{state | last_press: now_ms()}

    # The ramp. This sleep is what turns a fast thumb into a visible queue on
    # this process - and it costs no scheduler anything, unlike real work here
    # would with twenty five ships aboard.
    load_ms() > 0 && Process.sleep(load_ms())

    state = ship_one(state)
    {:noreply, state, remaining(state)}
  end

  def handle_cast(:resupply, %{hold: []} = state) do
    state = %{state | last_press: now_ms()}

    load_ms() > 0 && Process.sleep(load_ms())

    Events.emit(
      :refill,
      "#{state.name} TOOK ON A FRESH LOAD OF #{String.upcase(state.cargo_type)}"
    )

    state = %{
      state
      | hold: Cargo.build_hold(state.cargo_type),
        hold_count: state.hold_size,
        refills: state.refills + 1
    }

    publish(state)
    broadcast(state, true)
    {:noreply, state, remaining(state)}
  end

  # Resupply with cargo still aboard is a stale press from a laggy phone.
  def handle_cast(:resupply, state) do
    {:noreply, %{state | last_press: now_ms()}, remaining(state)}
  end

  # A cockpit at the controls. A second one - a reload, a reconnect, another
  # tab - simply replaces the first; whichever is watching last is the crew.
  def handle_cast({:board, pid}, state) do
    state = state |> cancel_leaving() |> watch(pid)
    {:noreply, state, remaining(state)}
  end

  @impl true
  def handle_info(:timeout, state) do
    Events.emit(:undock, "#{state.name} DRIFTED OFF - IDLE TIMEOUT")
    {:stop, :normal, state}
  end

  # The cockpit went dark. Not undocked yet: a reload boards again within the
  # grace and nothing happened. Only silence past it is a visitor who left.
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{crew: {_crew, ref}} = state) do
    timer = Process.send_after(self(), :crew_gone, grace_ms())
    {:noreply, %{state | crew: nil, leaving: timer}, remaining(state)}
  end

  def handle_info(:crew_gone, %{crew: nil} = state) do
    Hangar.park(state)
    Events.emit(:undock, "#{state.name} CREW OFFLINE - WAITING IN THE HANGAR")
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

  # Back from the hangar: same name, same cargo type, same counters. The hold
  # is rebuilt to the count it had - cargo is random bytes, nobody kept them.
  defp restore(state, parked) do
    %{
      state
      | hold: Cargo.build_hold(state.cargo_type, parked.hold_count),
        hold_count: parked.hold_count,
        delivered: parked.delivered,
        refills: parked.refills
    }
  end

  defp watch(%{crew: {_pid, old_ref}} = state, pid) do
    Process.demonitor(old_ref, [:flush])
    watch(%{state | crew: nil}, pid)
  end

  defp watch(state, pid), do: %{state | crew: {pid, Process.monitor(pid)}}

  defp cancel_leaving(%{leaving: nil} = state), do: state

  defp cancel_leaving(%{leaving: timer} = state) do
    Process.cancel_timer(timer)
    %{state | leaving: nil}
  end

  defp ship_one(%{hold: [container | rest]} = state) do
    Warehouse.accept(state.slug, container)

    state = %{
      state
      | hold: rest,
        hold_count: state.hold_count - 1,
        delivered: state.delivered + 1
    }

    publish(state)
    broadcast(state, false)
    state
  end

  # The cockpit animates on this, not on the press: a crate flies when the
  # container actually leaves the ship, which is after the ramp - so a backed
  # up ship visibly works through its mailbox one flight at a time.
  defp broadcast(state, refilled?) do
    Phoenix.PubSub.broadcast(
      Station.PubSub,
      topic(state.slug),
      {:shipped, %{hold: state.hold_count, delivered: state.delivered, refilled?: refilled?}}
    )
  end

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
      docked_at: state.docked_at,
      berth: state.berth
    }

    :ets.insert(DockingBay.status_table(), {state.name, snapshot})
  end

  # Idle means nobody is pressing the button, not that nobody is looking at the
  # page - and since status/1 stopped sending messages entirely, only presses
  # and this timeout ever reach the mailbox's clock.
  defp remaining(state), do: max(ttl() - (now_ms() - state.last_press), 0)

  defp ttl, do: Application.fetch_env!(:station, :ship_ttl_ms)

  defp grace_ms, do: Application.fetch_env!(:station, :ship_leave_grace_ms)

  defp load_ms, do: Application.fetch_env!(:station, :ship_load_ms)

  defp now_ms, do: System.monotonic_time(:millisecond)
end
