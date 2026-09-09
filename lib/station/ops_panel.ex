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

  @type settings :: %{
          warehouse_mode: Warehouse.mode(),
          hauler_boost: pos_integer(),
          freighters: non_neg_integer(),
          yield_to_visitors: boolean()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec settings() :: settings()
  def settings, do: :persistent_term.get(@term_key, defaults())

  @spec warehouse_mode() :: Warehouse.mode()
  def warehouse_mode, do: settings().warehouse_mode

  @spec hauler_boost() :: pos_integer()
  def hauler_boost, do: settings().hauler_boost

  @doc "How many simulated visitors are on duty."
  @spec freighters() :: non_neg_integer()
  def freighters, do: settings().freighters

  @doc "Whether freighters make room for people as they dock."
  @spec yield_to_visitors?() :: boolean()
  def yield_to_visitors?, do: settings().yield_to_visitors

  @doc "The named traffic levels from config, for whoever is typing at the shell."
  @spec traffic_levels() :: %{atom() => non_neg_integer()}
  def traffic_levels, do: Application.fetch_env!(:station, :traffic_levels)

  @spec set_warehouse_mode(Warehouse.mode()) :: :ok
  def set_warehouse_mode(mode) when mode in [:single_clerk, :inspection_crew] do
    GenServer.call(__MODULE__, {:set_warehouse_mode, mode})
  end

  @doc "Sends out more haulers. Multiplies the baseline, so the drop is quick."
  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor) when is_integer(factor) and factor >= 1 do
    GenServer.call(__MODULE__, {:set_hauler_boost, factor})
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

  @doc "Kills the warehouse. Its supervisor restarts it, ETS survives, cargo does not."
  @spec restart_warehouse() :: :ok
  def restart_warehouse, do: GenServer.call(__MODULE__, :restart_warehouse)

  @doc """
  Empties the warehouse and its mailbox, now.

  A flush would queue behind the very backlog it is meant to remove, so this
  stops the process through its supervisor and starts it again - an orderly
  stop, not a crash, so it does not count towards the restart intensity the
  way `restart_warehouse/0` does. Everything on the shelf and everything
  waiting is gone; the leaderboard keeps every delivery.
  """
  @spec clear_warehouse() :: :ok
  def clear_warehouse, do: GenServer.call(__MODULE__, :clear_warehouse)

  @spec reset_leaderboard() :: :ok
  def reset_leaderboard, do: GenServer.call(__MODULE__, :reset_leaderboard)

  @doc "Back to a clean station: no ships, no cargo, counters at zero. The fleet stays."
  @spec reset_station() :: :ok
  def reset_station, do: GenServer.call(__MODULE__, :reset_station)

  @impl true
  def init(_opts) do
    put(defaults())
    {:ok, %{}}
  end

  @impl true
  def handle_call({:set_warehouse_mode, mode}, _from, state) do
    apply_warehouse_mode(mode)
    Events.emit(:ops, "WAREHOUSE MODE -> #{mode |> to_string() |> String.upcase()}")
    {:reply, :ok, state}
  end

  def handle_call({:set_hauler_boost, factor}, _from, state) do
    TrafficControl.set_hauler_boost(factor)
    update(:hauler_boost, factor)
    Events.emit(:ops, "HAULERS DISPATCHED - x#{factor} CREW ON DUTY")
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

  def handle_call(:restart_warehouse, _from, state) do
    Events.emit(:ops, "WAREHOUSE RESTART REQUESTED BY OPS", :warning)
    Process.whereis(Warehouse) |> Process.exit(:kill)
    {:reply, :ok, state}
  end

  def handle_call(:clear_warehouse, _from, state) do
    :ok = Supervisor.terminate_child(Station.Game, Warehouse)
    {:ok, _pid} = Supervisor.restart_child(Station.Game, Warehouse)
    Metrics.put(:queue, 0)
    Events.emit(:ops, "WAREHOUSE CLEARED BY OPS", :warning)
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

  # The warehouse reads this setting per container, so the order here is the
  # order that never leaves it routing cargo at a crew which is not there: put
  # the crew on shift before the switch, and take it off after.
  defp apply_warehouse_mode(:inspection_crew) do
    InspectionCrew.staff(InspectionCrew.default_size())
    update(:warehouse_mode, :inspection_crew)
  end

  defp apply_warehouse_mode(:single_clerk) do
    update(:warehouse_mode, :single_clerk)
    InspectionCrew.dismiss()
  end

  defp update(key, value), do: settings() |> Map.put(key, value) |> put()

  defp put(settings), do: :persistent_term.put(@term_key, settings)

  defp defaults do
    %{
      warehouse_mode: Application.fetch_env!(:station, :warehouse_mode),
      hauler_boost: 1,
      freighters: Application.fetch_env!(:station, :freighters),
      yield_to_visitors: Application.fetch_env!(:station, :yield_to_visitors)
    }
  end
end
