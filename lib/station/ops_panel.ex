defmodule Station.OpsPanel do
  @moduledoc """
  The two switches the booth staff actually touch, plus the housekeeping ones.

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

  @type settings :: %{
          warehouse_mode: Warehouse.mode(),
          traffic: TrafficControl.level(),
          hauler_boost: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec settings() :: settings()
  def settings, do: :persistent_term.get(@term_key, defaults())

  @spec warehouse_mode() :: Warehouse.mode()
  def warehouse_mode, do: settings().warehouse_mode

  @spec traffic() :: TrafficControl.level()
  def traffic, do: settings().traffic

  @spec hauler_boost() :: pos_integer()
  def hauler_boost, do: settings().hauler_boost

  @spec set_warehouse_mode(Warehouse.mode()) :: :ok
  def set_warehouse_mode(mode) when mode in [:single_clerk, :inspection_crew] do
    GenServer.call(__MODULE__, {:set_warehouse_mode, mode})
  end

  @spec set_traffic(TrafficControl.level()) :: :ok
  def set_traffic(level), do: GenServer.call(__MODULE__, {:set_traffic, level})

  @doc "Sends out more haulers. Multiplies the baseline, so the drop is quick."
  @spec set_hauler_boost(pos_integer()) :: :ok
  def set_hauler_boost(factor) when is_integer(factor) and factor >= 1 do
    GenServer.call(__MODULE__, {:set_hauler_boost, factor})
  end

  @doc "Kills the warehouse. Its supervisor restarts it, ETS survives, cargo does not."
  @spec restart_warehouse() :: :ok
  def restart_warehouse, do: GenServer.call(__MODULE__, :restart_warehouse)

  @spec reset_leaderboard() :: :ok
  def reset_leaderboard, do: GenServer.call(__MODULE__, :reset_leaderboard)

  @doc "Back to a clean station: no ships, no cargo, counters at zero."
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

  def handle_call({:set_traffic, level}, _from, state) do
    TrafficControl.set_level(level)
    update(:traffic, level)
    Events.emit(:ops, "TRAFFIC -> #{level |> to_string() |> String.upcase()}")
    {:reply, :ok, state}
  end

  def handle_call({:set_hauler_boost, factor}, _from, state) do
    TrafficControl.set_hauler_boost(factor)
    update(:hauler_boost, factor)
    Events.emit(:ops, "HAULERS DISPATCHED - x#{factor} CREW ON DUTY")
    {:reply, :ok, state}
  end

  def handle_call(:restart_warehouse, _from, state) do
    Events.emit(:ops, "WAREHOUSE RESTART REQUESTED BY OPS", :warning)
    Process.whereis(Warehouse) |> Process.exit(:kill)
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
      traffic: Application.fetch_env!(:station, :traffic),
      hauler_boost: 1
    }
  end
end
