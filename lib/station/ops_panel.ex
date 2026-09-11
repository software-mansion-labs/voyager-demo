defmodule Station.OpsPanel do
  @moduledoc """
  The switches the booth staff actually touch, plus the housekeeping ones.

  Settings live in `:persistent_term` as well as in this process, so a ship, a
  dashboard or the warehouse can read the current mode without sending anyone a
  message. Writes go through the GenServer, and the GenServer is the only thing
  allowed to move the rest of the station in response.
  """

  use GenServer

  alias Station.Events
  alias Station.InspectionCrew
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.TrafficControl
  alias Station.Warehouse

  @term_key {__MODULE__, :settings}

  @type traffic :: atom() | non_neg_integer()

  @typedoc """
  A rehearsed demo from `:scenarios` in config: an id, a title, the presenter's
  steps (which Voyager tab, what to open, what to see), and whichever of the
  tunable knobs it wants set.
  """
  @type scenario :: %{
          required(:id) => atom(),
          required(:title) => String.t(),
          required(:steps) => [String.t()],
          optional(:clerks) => pos_integer(),
          optional(:freighters) => non_neg_integer(),
          optional(:haulers) => non_neg_integer(),
          optional(:freighter_interval_ms) => pos_integer(),
          optional(:hauler_interval_ms) => pos_integer()
        }

  @type settings :: %{
          clerks: pos_integer(),
          haulers: non_neg_integer(),
          freighters: non_neg_integer(),
          yield_to_visitors: boolean(),
          show_qr: boolean(),
          freighter_interval_ms: pos_integer(),
          hauler_interval_ms: pos_integer()
        }

  # Pace limits, in milliseconds. The floor keeps an autoclicker's worth of
  # robots off the warehouse; the ceiling is "as good as off".
  @min_interval_ms 100
  @max_interval_ms :timer.hours(1)

  # Two rows of four lanes on the television; more clerks than that would be a
  # number without a picture.
  @max_clerks 8
  @max_haulers 99

  # The knobs a scenario may set. Everything else on the panel (yield, QR) is
  # about the room, not the demo, and a preset leaves it alone.
  @scenario_keys [:clerks, :freighters, :haulers, :freighter_interval_ms, :hauler_interval_ms]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec settings() :: settings()
  def settings, do: :persistent_term.get(@term_key, defaults())

  @doc "How many haulers are on duty."
  @spec haulers() :: non_neg_integer()
  def haulers, do: settings().haulers

  @spec max_haulers() :: pos_integer()
  def max_haulers, do: @max_haulers

  @doc "How many clerks are on shift."
  @spec clerks() :: pos_integer()
  def clerks, do: settings().clerks

  @spec max_clerks() :: pos_integer()
  def max_clerks, do: @max_clerks

  @doc "One clerk per scheduler, capped at what the television can draw."
  @spec default_clerks() :: pos_integer()
  def default_clerks, do: InspectionCrew.default_size() |> min(@max_clerks) |> max(2)

  @doc "Whether the television shows the QR codes."
  @spec show_qr?() :: boolean()
  def show_qr?, do: settings().show_qr

  @doc "How often each freighter sends a container, in milliseconds."
  @spec freighter_interval_ms() :: pos_integer()
  def freighter_interval_ms, do: settings().freighter_interval_ms

  @doc "How often each hauler comes to collect, in milliseconds."
  @spec hauler_interval_ms() :: pos_integer()
  def hauler_interval_ms, do: settings().hauler_interval_ms

  @spec interval_bounds() :: {pos_integer(), pos_integer()}
  def interval_bounds, do: {@min_interval_ms, @max_interval_ms}

  @doc "How many simulated visitors are on duty."
  @spec freighters() :: non_neg_integer()
  def freighters, do: settings().freighters

  @doc "Whether freighters make room for people as they dock."
  @spec yield_to_visitors?() :: boolean()
  def yield_to_visitors?, do: settings().yield_to_visitors

  @doc "The named traffic levels from config, for whoever is typing at the shell."
  @spec traffic_levels() :: %{atom() => non_neg_integer()}
  def traffic_levels, do: Application.fetch_env!(:station, :traffic_levels)

  @doc """
  How many clerks inspect cargo.

  Always clerk processes, never the warehouse itself. One is the bottleneck:
  every container waits in one mailbox while the warehouse only routes. More
  spread the load across the schedulers and the queue drains.
  """
  @spec set_clerks(pos_integer()) :: :ok
  def set_clerks(count) when is_integer(count) and count >= 1 and count <= @max_clerks do
    GenServer.call(__MODULE__, {:set_clerks, count})
  end

  @doc "Exactly this many haulers on duty. Zero is a warehouse nobody drains."
  @spec set_haulers(non_neg_integer()) :: :ok
  def set_haulers(count) when is_integer(count) and count >= 0 and count <= @max_haulers do
    GenServer.call(__MODULE__, {:set_haulers, count})
  end

  @doc "Sends out more haulers. Multiplies the configured baseline, so the drop is quick."
  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor) when is_integer(factor) and factor >= 1 do
    set_haulers(min(Application.fetch_env!(:station, :haulers) * factor, @max_haulers))
  end

  @doc """
  How often each freighter sends a container. The freighters' count is the
  load and this is its other half: halve the interval and every level doubles.
  """
  @spec set_freighter_interval(pos_integer()) :: :ok
  def set_freighter_interval(ms)
      when is_integer(ms) and ms >= @min_interval_ms and ms <= @max_interval_ms do
    GenServer.call(__MODULE__, {:set_freighter_interval, ms})
  end

  @doc "How often each hauler comes to collect. The drain, per hauler."
  @spec set_hauler_interval(pos_integer()) :: :ok
  def set_hauler_interval(ms)
      when is_integer(ms) and ms >= @min_interval_ms and ms <= @max_interval_ms do
    GenServer.call(__MODULE__, {:set_hauler_interval, ms})
  end

  @doc "Shows or hides the QR codes on the television."
  @spec set_show_qr(boolean()) :: :ok
  def set_show_qr(show?) when is_boolean(show?) do
    GenServer.call(__MODULE__, {:set_show_qr, show?})
  end

  @doc """
  Simulated visitors, for a quiet aisle.

  Takes a level from `:traffic_levels` (`:off`, `:quiet`, `:normal`, `:rush`)
  or an exact number of freighters. Each freighter is one more process in the
  tree, sending cargo at a steady tap, and unlike visitors they do not divide
  the inspection cost - so the count is the load: quiet idles, normal sits near
  the line, rush congests the warehouse without a single visitor.
  """
  @spec set_traffic(traffic()) :: :ok | {:error, :unknown_level}
  def set_traffic(count) when is_integer(count) and count >= 0 and count <= 99 do
    GenServer.call(__MODULE__, {:set_traffic, count})
  end

  def set_traffic(level) when is_atom(level) do
    case Map.fetch(traffic_levels(), level) do
      {:ok, count} -> set_traffic(count)
      :error -> {:error, :unknown_level}
    end
  end

  @doc """
  Freighters yield to visitors.

  On, each docked visitor sends one freighter home, so `set_traffic(8)` means
  eight ships on the screen whoever they are. Off, the freighter count is what
  it says and visitors come on top.
  """
  @spec set_yield_to_visitors(boolean()) :: :ok
  def set_yield_to_visitors(yield?) when is_boolean(yield?) do
    GenServer.call(__MODULE__, {:set_yield_to_visitors, yield?})
  end

  @doc "The rehearsed demos from config, in the order they are told."
  @spec scenarios() :: [scenario()]
  def scenarios, do: Application.fetch_env!(:station, :scenarios)

  @doc """
  The settings a scenario puts in place: what it names, on top of the config
  baseline for everything it does not. The baseline, not the current setting,
  so a preset always lands on the same station whatever was pressed before.
  """
  @spec scenario_settings(scenario()) :: %{atom() => non_neg_integer()}
  def scenario_settings(scenario) do
    defaults() |> Map.take(@scenario_keys) |> Map.merge(Map.take(scenario, @scenario_keys))
  end

  @doc "The scenario the given (or current) settings match exactly, if any."
  @spec current_scenario(settings()) :: atom() | nil
  def current_scenario(settings \\ settings()) do
    live = Map.take(settings, @scenario_keys)
    Enum.find_value(scenarios(), fn s -> if scenario_settings(s) == live, do: s.id end)
  end

  @doc """
  Puts a scenario's settings in place in one go: clerks, traffic, haulers and
  both paces. Nothing is cleared - the shelf, the queues and the leaderboard
  are as they were, so the story can start from where the last one ended.
  """
  @spec apply_scenario(atom()) :: :ok | {:error, :unknown_scenario}
  def apply_scenario(id) when is_atom(id) do
    case Enum.find(scenarios(), &(&1.id == id)) do
      nil -> {:error, :unknown_scenario}
      scenario -> GenServer.call(__MODULE__, {:apply_scenario, scenario})
    end
  end

  @doc "Kills the warehouse. Its supervisor restarts it, ETS survives, cargo does not."
  @spec restart_warehouse() :: :ok
  def restart_warehouse, do: GenServer.call(__MODULE__, :restart_warehouse)

  @doc """
  Empties the warehouse, its mailbox and every clerk's mailbox, now.

  A flush would queue behind the very backlog it is meant to remove, so this
  stops the process through its supervisor and starts it again - an orderly
  stop, not a crash, so it does not count towards the restart intensity the
  way `restart_warehouse/0` does. With a crew on, the crew is replaced the
  same way, since that is where the backlog sits. Everything on the shelf and
  everything waiting anywhere is gone; the leaderboard keeps every delivery.
  """
  @spec clear_warehouse() :: :ok
  def clear_warehouse, do: GenServer.call(__MODULE__, :clear_warehouse)

  @spec reset_leaderboard() :: :ok
  def reset_leaderboard, do: GenServer.call(__MODULE__, :reset_leaderboard)

  @doc "The HAULED figure on the television back to zero. Cargo and shelf untouched."
  @spec reset_hauled() :: :ok
  def reset_hauled, do: GenServer.call(__MODULE__, :reset_hauled)

  @doc """
  Undocks every visitor's ship now, and forgets the ones waiting in the hangar.
  Their visitors get a fresh ship on the next scan. Cargo and counters stay.
  """
  @spec undock_visitors() :: :ok
  def undock_visitors, do: GenServer.call(__MODULE__, :undock_visitors)

  @doc "Back to a clean station: no ships, no cargo, counters at zero. The fleet stays."
  @spec reset_station() :: :ok
  def reset_station, do: GenServer.call(__MODULE__, :reset_station)

  @impl true
  def init(_opts) do
    put(defaults())
    {:ok, %{}}
  end

  # The warehouse reads who is on shift per container, straight from the crew's
  # own term, so the new shift takes the very next container - including the
  # ones already queued behind the switch.
  @impl true
  def handle_call({:set_clerks, count}, _from, state) do
    InspectionCrew.staff(count)
    update(:clerks, count)
    Events.emit(:ops, "INSPECTION -> #{count} #{if count == 1, do: "CLERK", else: "CLERKS"}")
    {:reply, :ok, state}
  end

  def handle_call({:set_haulers, count}, _from, state) do
    TrafficControl.set_haulers(count)
    update(:haulers, count)
    Events.emit(:ops, "HAULERS -> #{count} ON DUTY")
    {:reply, :ok, state}
  end

  def handle_call({:set_freighter_interval, ms}, _from, state) do
    update(:freighter_interval_ms, ms)
    Events.emit(:ops, "FREIGHTERS -> ONE CONTAINER EVERY #{ms} MS")
    {:reply, :ok, state}
  end

  def handle_call({:set_hauler_interval, ms}, _from, state) do
    update(:hauler_interval_ms, ms)
    Events.emit(:ops, "HAULERS -> COLLECTING EVERY #{ms} MS")
    {:reply, :ok, state}
  end

  def handle_call({:set_show_qr, show?}, _from, state) do
    update(:show_qr, show?)
    {:reply, :ok, state}
  end

  def handle_call({:set_traffic, count}, _from, state) do
    TrafficControl.set_freighters(count)
    update(:freighters, count)
    Events.emit(:ops, "TRAFFIC -> #{count} FREIGHTERS ON DUTY")
    {:reply, :ok, state}
  end

  def handle_call({:set_yield_to_visitors, yield?}, _from, state) do
    update(:yield_to_visitors, yield?)
    Station.Dispatcher.reconcile()
    Events.emit(:ops, "FREIGHTERS #{if yield?, do: "YIELD TO", else: "STAY FOR"} VISITORS")
    {:reply, :ok, state}
  end

  # Same moves as the individual switches, in the same order each makes them:
  # act on the station, then publish the setting. The paces are read by every
  # freighter and hauler on its next tick, so they need only the term.
  def handle_call({:apply_scenario, scenario}, _from, state) do
    target = scenario_settings(scenario)
    InspectionCrew.staff(target.clerks)
    TrafficControl.set_haulers(target.haulers)
    TrafficControl.set_freighters(target.freighters)
    settings() |> Map.merge(target) |> put()
    Events.emit(:ops, "SCENARIO -> #{String.upcase(scenario.title)}")
    {:reply, :ok, state}
  end

  def handle_call(:restart_warehouse, _from, state) do
    Events.emit(:ops, "WAREHOUSE RESTART REQUESTED BY OPS", :warning)
    Process.whereis(Warehouse) |> Process.exit(:kill)
    {:reply, :ok, state}
  end

  def handle_call(:clear_warehouse, _from, state) do
    # Warehouse first, so nothing new is routed; then the crew, whose
    # mailboxes are where the backlog lives - a fresh shift of the same size,
    # empty-handed; then the warehouse comes back.
    :ok = Supervisor.terminate_child(Station.Game, Warehouse)
    InspectionCrew.staff(clerks())
    {:ok, _pid} = Supervisor.restart_child(Station.Game, Warehouse)
    Metrics.put(:queue, 0)
    Metrics.put(:inspection_queue, 0)
    Events.emit(:ops, "WAREHOUSE AND QUEUES CLEARED BY OPS", :warning)
    {:reply, :ok, state}
  end

  def handle_call(:undock_visitors, _from, state) do
    docked = Station.DockingBay.count()
    Station.DockingBay.clear()
    Station.Hangar.clear()
    Events.emit(:ops, "#{docked} VISITOR SHIPS UNDOCKED BY OPS", :warning)
    {:reply, :ok, state}
  end

  def handle_call(:reset_hauled, _from, state) do
    Warehouse.reset_collected()
    Events.emit(:ops, "HAULED COUNTER RESET", :warning)
    {:reply, :ok, state}
  end

  def handle_call(:reset_leaderboard, _from, state) do
    Leaderboard.reset()
    Events.emit(:ops, "LEADERBOARD RESET", :warning)
    {:reply, :ok, state}
  end

  def handle_call(:reset_station, _from, state) do
    Station.DockingBay.clear()
    Warehouse.flush()
    Metrics.reset()
    Events.emit(:ops, "STATION RESET", :warning)
    {:reply, :ok, state}
  end

  defp update(key, value), do: settings() |> Map.put(key, value) |> put()

  defp put(settings), do: :persistent_term.put(@term_key, settings)

  defp defaults do
    %{
      clerks: Application.fetch_env!(:station, :clerks),
      haulers: Application.fetch_env!(:station, :haulers),
      freighters: Application.fetch_env!(:station, :freighters),
      yield_to_visitors: Application.fetch_env!(:station, :yield_to_visitors),
      show_qr: true,
      freighter_interval_ms: Application.fetch_env!(:station, :freighter_interval_ms),
      hauler_interval_ms: Application.fetch_env!(:station, :hauler_interval_ms)
    }
  end
end
