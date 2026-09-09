defmodule Station.Warehouse do
  @moduledoc """
  The single GenServer every ship sends cargo to. The hero of the demo.

  Everything about it is deliberate:

    * every container arrives as a `cast`, so a fast clicker piles up
      `message_queue_len` instead of blocking on a call
    * every container is inspected (checksummed) by a clerk before it is
      accepted, so the work is real and shows up as reductions - on the clerk
    * every accepted container is kept in process state, so memory grows into
      the fat process the whole industry hunts for in production

  This process only routes: each container goes to the next clerk in
  `Station.InspectionCrew` and comes back checksummed to be stored. With one
  clerk on shift the queue climbs into the hundreds in that clerk's mailbox;
  with a crew it drains in front of the audience and the load spreads across
  every scheduler.

  Who is on shift is read per container from a persistent term, never held in
  this process's state. A container costs half a second to clear, so a shift
  change arriving as a message would sit behind the backlog it is meant to fix:
  at a queue of a hundred, ops would press the button and watch nothing happen
  for a minute. Read from the term, the very next container goes to the new crew.
  """

  use GenServer

  alias Station.Cargo
  alias Station.Events
  alias Station.InspectionCrew
  alias Station.Leaderboard
  alias Station.Metrics

  @gc_threshold 8 * 1024 * 1024

  # What is on the shelf, per cargo type, for the television to draw one tile
  # per container without asking this process anything. Owned by this process
  # on purpose: when the warehouse dies, its cargo dies, and so does the table.
  @shelf :station_warehouse_shelf

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Hands one container to the warehouse. Fire and forget, on purpose.

  `ship` is the slug of a visitor's ship, or `nil` for the background fleet.
  The fleet's cargo counts towards every metric on the wall but never towards
  the leaderboard: a booth where the robots outscore the humans by a factor of
  fifty has no leaderboard worth looking for your own name on.
  """
  @spec accept(String.t() | nil, Cargo.container()) :: :ok
  def accept(ship, container), do: GenServer.cast(__MODULE__, {:accept, ship, container})

  @doc "A hauler asking for cargo to take away."
  @spec collect(pid(), pos_integer()) :: :ok
  def collect(hauler, count), do: GenServer.cast(__MODULE__, {:collect, hauler, count})

  @doc "Result coming back from a clerk."
  @spec inspected(String.t(), Cargo.container()) :: :ok
  def inspected(ship, container), do: GenServer.cast(__MODULE__, {:inspected, ship, container})

  @doc "Empties the warehouse without restarting it."
  @spec flush() :: :ok
  def flush, do: GenServer.cast(__MODULE__, :flush)

  @doc """
  Containers on the shelf, per cargo type. Read from ETS, never asked.

  Empty while the warehouse is between a crash and its restart - which is the
  truth: the shelf died with the process.
  """
  @spec shelf() :: %{Cargo.type() => non_neg_integer()}
  def shelf do
    for {type, count} <- rows(), is_binary(type), into: %{}, do: {type, count}
  end

  @doc """
  Containers handed to haulers so far, per cargo type. Cumulative, so the
  television colours each outgoing crate from the real difference between two
  ticks rather than guessing from what the shelf lost.
  """
  @spec collected() :: %{Cargo.type() => non_neg_integer()}
  def collected do
    for {{:collected, type}, count} <- rows(), into: %{}, do: {type, count}
  end

  defp rows do
    case :ets.whereis(@shelf) do
      :undefined -> []
      _ref -> :ets.tab2list(@shelf)
    end
  end

  @doc """
  Everything the dashboards need, read from outside the process.

  Never a `GenServer.call` - the warehouse is the process we deliberately
  congest, so asking it about itself would queue behind the cargo. The live
  numbers are sampled by `Station.Watchdog` into `Station.Metrics`.
  """
  @spec stats() :: map()
  def stats do
    %{
      alive?: Process.whereis(__MODULE__) != nil,
      queue: Metrics.get(:queue),
      # Containers handed to the clerks and not yet checksummed: with one
      # clerk on shift, this is the bottleneck's queue.
      inspection_queue: Metrics.get(:inspection_queue),
      backlog: Metrics.get(:queue) + Metrics.get(:inspection_queue),
      memory: Metrics.get(:warehouse_memory),
      reductions: Metrics.get(:warehouse_reductions),
      stored: Metrics.get(:stored),
      stored_bytes: Metrics.get(:stored_bytes),
      accepted: Metrics.get(:accepted),
      inspected: Metrics.get(:inspected),
      dropped: Metrics.get(:dropped),
      collected: Metrics.get(:collected)
    }
  end

  @impl true
  def init(_opts) do
    Metrics.add(:stored, -Metrics.get(:stored))
    Metrics.add(:stored_bytes, -Metrics.get(:stored_bytes))

    if :ets.whereis(@shelf) == :undefined do
      :ets.new(@shelf, [:set, :public, :named_table, read_concurrency: true])
    end

    clear_shelf()

    state = %{
      cargo: :queue.new(),
      count: 0,
      bytes: 0,
      capacity: Application.fetch_env!(:station, :warehouse_capacity),
      gc_watermark: 0,
      sizes: Map.new(Cargo.presets(), fn {type, _} -> {type, Cargo.container_bytes(type)} end),
      next: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:accept, ship, container}, state) do
    {:noreply, route(state, ship, container, InspectionCrew.on_shift())}
  end

  def handle_cast({:inspected, ship, container}, state) do
    {:noreply, store(state, ship, container)}
  end

  def handle_cast({:collect, hauler, count}, state) do
    {taken, state} = take(state, count, [])

    if taken != [] do
      send(hauler, {:cargo_collected, taken})
      Metrics.add(:collected, length(taken))

      taken
      |> Enum.frequencies_by(fn {_ship, container} -> container.type end)
      |> Enum.each(fn {type, n} ->
        :ets.update_counter(@shelf, {:collected, type}, n, {{:collected, type}, 0})
      end)
    end

    {:noreply, collect_garbage(state)}
  end

  def handle_cast(:flush, state) do
    Metrics.sub(:stored, state.count)
    Metrics.sub(:stored_bytes, state.bytes)
    clear_shelf()
    {:noreply, %{state | cargo: :queue.new(), count: 0, bytes: 0}}
  end

  # Nobody on shift - the instant of a shift change, or the crew's supervisor
  # restarting. Rather than drop the container, the warehouse checks this one
  # itself; the next one goes to a clerk again.
  defp route(state, ship, container, {}) do
    _checksum = Cargo.inspect_container(container)
    Metrics.add(:inspected, 1)
    store(state, ship, container)
  end

  defp route(state, ship, container, crew) do
    clerk = elem(crew, rem(state.next, tuple_size(crew)))
    InspectionCrew.dispatch(clerk, ship, container)
    %{state | next: state.next + 1}
  end

  defp store(state, ship, container) do
    Metrics.add(:accepted, 1)
    if ship, do: Leaderboard.record(ship, container.type)

    bytes = Map.fetch!(state.sizes, container.type)

    state =
      %{
        state
        | cargo: :queue.in({ship, container}, state.cargo),
          count: state.count + 1,
          bytes: state.bytes + bytes
      }

    Metrics.add(:stored, 1)
    Metrics.add(:stored_bytes, bytes)
    :ets.update_counter(@shelf, container.type, 1)

    enforce_capacity(state)
  end

  # Above capacity the oldest cargo goes over the side. Without this the demo
  # eventually eats the box it runs on.
  #
  # Jettisoned a batch at a time rather than one container per message: at the
  # ceiling every single arrival is an overflow, and one-in-one-out would put an
  # identical line on the television several hundred times a second.
  defp enforce_capacity(%{count: count, capacity: capacity} = state) when count <= capacity do
    state
  end

  defp enforce_capacity(state) do
    overflow = max(state.count - state.capacity, div(state.capacity, 20))
    {dropped, state} = take(state, overflow, [])

    Metrics.add(:dropped, length(dropped))

    Events.emit(
      :cargo_dropped,
      "WAREHOUSE OVER CAPACITY - #{length(dropped)} CONTAINERS JETTISONED",
      :warning
    )

    state
  end

  # Dropping references is not the same as giving the memory back: the process
  # heap keeps its size until it is collected, and a GenServer holding hundreds
  # of megabytes may sit on them for a long time. That would quietly break the
  # producer/consumer demo, where dispatching haulers has to make the memory
  # fall while somebody is watching. So once enough has been hauled away, the
  # warehouse collects its own garbage - which costs it a pause, in its own
  # process, exactly like it would in production.
  defp collect_garbage(%{bytes: bytes, gc_watermark: watermark} = state)
       when bytes < watermark - @gc_threshold do
    :erlang.garbage_collect()
    %{state | gc_watermark: bytes}
  end

  defp collect_garbage(%{bytes: bytes, gc_watermark: watermark} = state) when bytes > watermark do
    %{state | gc_watermark: bytes}
  end

  defp collect_garbage(state), do: state

  defp clear_shelf do
    for type <- Map.keys(Cargo.presets()), do: :ets.insert(@shelf, {type, 0})
    :ok
  end

  defp take(state, 0, acc), do: {Enum.reverse(acc), state}

  defp take(state, count, acc) do
    case :queue.out(state.cargo) do
      {{:value, {_ship, container} = entry}, rest} ->
        bytes = Map.fetch!(state.sizes, container.type)
        Metrics.sub(:stored, 1)
        Metrics.sub(:stored_bytes, bytes)
        :ets.update_counter(@shelf, container.type, -1)

        state = %{state | cargo: rest, count: state.count - 1, bytes: state.bytes - bytes}
        take(state, count - 1, [entry | acc])

      {:empty, _} ->
        {Enum.reverse(acc), state}
    end
  end
end
