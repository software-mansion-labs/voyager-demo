defmodule Station.Warehouse do
  @moduledoc """
  The single GenServer every ship sends cargo to. The hero of the demo.

  Everything about it is deliberate:

    * every container arrives as a `cast`, so a fast clicker piles up
      `message_queue_len` instead of blocking on a call
    * every container is inspected (checksummed) before it is accepted, so the
      work is real and shows up as reductions
    * every accepted container is kept in process state, so memory grows into
      the fat process the whole industry hunts for in production

  In `:single_clerk` mode the inspection runs here, in this process, and the
  queue climbs into the hundreds. In `:inspection_crew` mode this process only
  routes work to `Station.InspectionCrew` and merges the results, the queue
  drains in front of the audience and the load spreads across every scheduler.

  Which mode it is in is read per container from `Station.OpsPanel`, never held
  in this process's state. A container costs half a second to clear, so a switch
  arriving as a message would sit behind the backlog it is meant to fix: at a
  queue of a hundred, ops would press the button and watch nothing happen for a
  minute. Read from a persistent term, the very next container goes to the crew.
  """

  use GenServer

  alias Station.Cargo
  alias Station.Events
  alias Station.InspectionCrew
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.OpsPanel

  @type mode :: :single_clerk | :inspection_crew

  @gc_threshold 8 * 1024 * 1024

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

  @doc "Result coming back from an inspector, in `:inspection_crew` mode."
  @spec inspected(String.t(), Cargo.container()) :: :ok
  def inspected(ship, container), do: GenServer.cast(__MODULE__, {:inspected, ship, container})

  @doc "Empties the warehouse without restarting it."
  @spec flush() :: :ok
  def flush, do: GenServer.cast(__MODULE__, :flush)

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
      memory: Metrics.get(:warehouse_memory),
      reductions: Metrics.get(:warehouse_reductions),
      stored: Metrics.get(:stored),
      stored_bytes: Metrics.get(:stored_bytes),
      accepted: Metrics.get(:accepted),
      inspected: Metrics.get(:inspected),
      dropped: Metrics.get(:dropped),
      collected: Metrics.get(:collected),
      mode: OpsPanel.warehouse_mode()
    }
  end

  @impl true
  def init(_opts) do
    Metrics.add(:stored, -Metrics.get(:stored))
    Metrics.add(:stored_bytes, -Metrics.get(:stored_bytes))

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
    {:noreply, route(state, ship, container, crew())}
  end

  def handle_cast({:inspected, ship, container}, state) do
    {:noreply, store(state, ship, container)}
  end

  def handle_cast({:collect, hauler, count}, state) do
    {taken, state} = take(state, count, [])

    if taken != [] do
      send(hauler, {:cargo_collected, taken})
      Metrics.add(:collected, length(taken))
    end

    {:noreply, collect_garbage(state)}
  end

  def handle_cast(:flush, state) do
    Metrics.sub(:stored, state.count)
    Metrics.sub(:stored_bytes, state.bytes)
    {:noreply, %{state | cargo: :queue.new(), count: 0, bytes: 0}}
  end

  # An empty crew is both modes' fallback: single clerk by choice, and
  # inspection crew in the moment before anybody has been put on shift.
  defp crew do
    case OpsPanel.warehouse_mode() do
      :inspection_crew -> InspectionCrew.on_shift()
      :single_clerk -> {}
    end
  end

  defp route(state, ship, container, {}) do
    _checksum = Cargo.inspect_container(container)
    Metrics.add(:inspected, 1)
    store(state, ship, container)
  end

  defp route(state, ship, container, crew) do
    inspector = elem(crew, rem(state.next, tuple_size(crew)))
    InspectionCrew.dispatch(inspector, ship, container)
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

  defp take(state, 0, acc), do: {Enum.reverse(acc), state}

  defp take(state, count, acc) do
    case :queue.out(state.cargo) do
      {{:value, {_ship, container} = entry}, rest} ->
        bytes = Map.fetch!(state.sizes, container.type)
        Metrics.sub(:stored, 1)
        Metrics.sub(:stored_bytes, bytes)

        state = %{state | cargo: rest, count: state.count - 1, bytes: state.bytes - bytes}
        take(state, count - 1, [entry | acc])

      {:empty, _} ->
        {Enum.reverse(acc), state}
    end
  end
end
