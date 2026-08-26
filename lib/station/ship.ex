defmodule Station.Ship do
  @moduledoc """
  One visitor, as a named process in the station's supervision tree.

  The whole trick of the demo is that there is nothing behind this. A ship is a
  GenServer holding a hold full of containers in its state. Pressing TRANSFER
  sends exactly one message to `Station.Warehouse` and removes exactly one
  container from here - which is why the ship's memory falls and the
  warehouse's rises, live, in Voyager.

  Two limits sit in this process rather than in the browser, because a cookie
  clicker on a public URL invites autoclickers: a token bucket per ship, and a
  harder ceiling while the warehouse is congested. The second one is what makes
  the phone feel the backpressure in the thumb.
  """

  use GenServer, restart: :temporary

  alias Station.Cargo
  alias Station.Events
  alias Station.Metrics
  alias Station.ShipNames
  alias Station.Warehouse

  @type transfer_result ::
          {:ok, %{hold: non_neg_integer(), delivered: non_neg_integer(), refilled?: boolean()}}
          | {:throttled, non_neg_integer()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "One click. One container. One message."
  @spec transfer(atom()) :: transfer_result() | {:error, :gone}
  def transfer(name), do: safe_call(name, :transfer)

  @spec status(atom()) :: map() | {:error, :gone}
  def status(name), do: safe_call(name, :status)

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
    slug = ShipNames.to_slug(name)

    state = %{
      name: name,
      slug: slug,
      cargo_type: cargo_type,
      hold: Cargo.build_hold(cargo_type),
      hold_count: Cargo.hold_size(),
      hold_size: Cargo.hold_size(),
      delivered: 0,
      tokens: max_rate(),
      last_refill: now_ms(),
      last_press: now_ms(),
      docked_at: System.system_time(:second)
    }

    Metrics.add(:ships_docked, 1)
    Events.emit(:dock, "#{name} DOCKED - #{String.upcase(cargo_type)}")

    {:ok, state, ttl()}
  end

  @impl true
  def handle_call(:transfer, _from, state) do
    # A throttled press still counts as a thumb on the button, so it keeps the
    # ship alive the same way a successful one does.
    state = %{state | last_press: now_ms()}

    case take_token(state) do
      {:deny, retry_in, state} ->
        Metrics.add(:throttled, 1)
        {:reply, {:throttled, retry_in}, state, remaining(state)}

      {:allow, state} ->
        {reply, state} = ship_one(state)
        {:reply, reply, state, remaining(state)}
    end
  end

  def handle_call(:status, _from, state), do: {:reply, snapshot(state), state, remaining(state)}

  @impl true
  def handle_info(:timeout, state) do
    Events.emit(:undock, "#{state.name} DRIFTED OFF - IDLE TIMEOUT")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state, remaining(state)}

  @impl true
  def terminate(_reason, state) do
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

    {refilled?, state} = refill_if_empty(state)

    {{:ok, %{hold: state.hold_count, delivered: state.delivered, refilled?: refilled?}}, state}
  end

  defp refill_if_empty(%{hold: []} = state) do
    Events.emit(
      :refill,
      "#{state.name} TOOK ON A FRESH LOAD OF #{String.upcase(state.cargo_type)}"
    )

    {true, %{state | hold: Cargo.build_hold(state.cargo_type), hold_count: state.hold_size}}
  end

  defp refill_if_empty(state), do: {false, state}

  # Token bucket, refilled continuously. The ceiling drops while the warehouse
  # is backed up, so a congested station physically slows every thumb in the room.
  defp take_token(state) do
    now = now_ms()
    rate = current_rate()
    elapsed = now - state.last_refill

    tokens = min(rate * 1.0, state.tokens + elapsed * rate / 1000)
    state = %{state | tokens: tokens, last_refill: now}

    if tokens >= 1.0 do
      {:allow, %{state | tokens: tokens - 1.0}}
    else
      {:deny, ceil((1.0 - tokens) * 1000 / rate), state}
    end
  end

  defp current_rate do
    limits = Application.fetch_env!(:station, :transfer_limits)

    if Metrics.get(:queue) >= limits[:congested_queue] do
      limits[:congested_per_second]
    else
      limits[:per_second]
    end
  end

  defp max_rate, do: Application.fetch_env!(:station, :transfer_limits)[:per_second] * 1.0

  defp snapshot(state) do
    %{
      name: state.name,
      slug: state.slug,
      cargo_type: state.cargo_type,
      hold: state.hold_count,
      hold_size: state.hold_size,
      delivered: state.delivered,
      pid: inspect(self()),
      memory: Process.info(self(), :memory) |> elem(1),
      docked_at: state.docked_at
    }
  end

  defp safe_call(name, message) do
    GenServer.call(name, message)
  catch
    :exit, _ -> {:error, :gone}
  end

  # Idle means nobody is pressing the button, not that nobody is looking at the
  # page. The cockpit polls this process once a second to redraw its counters,
  # so measuring from the last message would keep a ship docked for as long as
  # a tab is open somewhere - and at a booth with a queue behind it, an
  # abandoned tab holding one of twenty five berths is the expensive case.
  defp remaining(state), do: max(ttl() - (now_ms() - state.last_press), 0)

  defp ttl, do: Application.fetch_env!(:station, :ship_ttl_ms)

  defp now_ms, do: System.monotonic_time(:millisecond)
end
