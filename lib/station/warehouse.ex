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
  """

  use GenServer

  alias Station.Cargo
  alias Station.Events
  alias Station.InspectionCrew
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.OpsPanel

  @type mode :: :single_clerk | :inspection_crew

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Hands one container to the warehouse. Fire and forget, on purpose."
  @spec accept(String.t(), Cargo.container()) :: :ok
  def accept(ship, container), do: GenServer.cast(__MODULE__, {:accept, ship, container})

  @doc "A hauler asking for cargo to take away."
  @spec collect(pid(), pos_integer()) :: :ok
  def collect(hauler, count), do: GenServer.cast(__MODULE__, {:collect, hauler, count})

  @doc "Result coming back from an inspector, in `:inspection_crew` mode."
  @spec inspected(String.t(), Cargo.container()) :: :ok
  def inspected(ship, container), do: GenServer.cast(__MODULE__, {:inspected, ship, container})

  @spec set_mode(mode()) :: :ok
  def set_mode(mode) when mode in [:single_clerk, :inspection_crew] do
    GenServer.cast(__MODULE__, {:set_mode, mode})
  end

  @doc "Tells the warehouse the inspector pool changed size."
  @spec crew_changed() :: :ok
  def crew_changed, do: GenServer.cast(__MODULE__, :crew_changed)

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
      mode: OpsPanel.warehouse_mode(),
      sizes: Map.new(Cargo.presets(), fn {type, _} -> {type, Cargo.container_bytes(type)} end),
      crew: {},
      crew_size: 0,
      next: 0
    }

    {:ok, refresh_crew(state)}
  end

  @impl true
  def handle_cast({:accept, ship, container}, %{mode: :single_clerk} = state) do
    _checksum = Cargo.inspect_container(container)
    Metrics.add(:inspected, 1)
    {:noreply, store(state, ship, container)}
  end

  def handle_cast({:accept, ship, container}, %{mode: :inspection_crew, crew_size: 0} = state) do
    _checksum = Cargo.inspect_container(container)
    Metrics.add(:inspected, 1)
    {:noreply, store(state, ship, container)}
  end

  def handle_cast({:accept, ship, container}, %{mode: :inspection_crew} = state) do
    inspector = elem(state.crew, rem(state.next, state.crew_size))
    InspectionCrew.dispatch(inspector, ship, container)
    {:noreply, %{state | next: state.next + 1}}
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

    {:noreply, state}
  end

  def handle_cast({:set_mode, mode}, state) do
    {:noreply, refresh_crew(%{state | mode: mode})}
  end

  def handle_cast(:crew_changed, state) do
    {:noreply, refresh_crew(state)}
  end

  def handle_cast(:flush, state) do
    Metrics.sub(:stored, state.count)
    Metrics.sub(:stored_bytes, state.bytes)
    {:noreply, %{state | cargo: :queue.new(), count: 0, bytes: 0}}
  end

  defp refresh_crew(state) do
    crew = InspectionCrew.workers() |> List.to_tuple()
    %{state | crew: crew, crew_size: tuple_size(crew), next: 0}
  end

  defp store(state, ship, container) do
    Metrics.add(:accepted, 1)
    Leaderboard.record(ship, container.type)

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
  defp enforce_capacity(%{count: count, capacity: capacity} = state) when count <= capacity do
    state
  end

  defp enforce_capacity(state) do
    overflow = state.count - state.capacity
    {dropped, state} = take(state, overflow, [])

    Metrics.add(:dropped, length(dropped))

    Events.emit(
      :cargo_dropped,
      "WAREHOUSE OVER CAPACITY - #{length(dropped)} CONTAINERS JETTISONED",
      :warning
    )

    state
  end

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
