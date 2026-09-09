defmodule Station.DockingBay do
  @moduledoc """
  Where visitors' ships live: a DynamicSupervisor whose children are the people
  standing in front of the booth.

  There is no registration. Scanning the code docks a ship: the bay picks a
  name from `Station.ShipNames`' fixed pool and a cargo type at random, and the
  visitor is a process in the tree before the page has finished loading.

  It owns the two decisions that keep that safe. The live ship cap is set for
  the human eye, not for the runtime - eight ships is one legible column on a
  television, and the BEAM would carry eight thousand. Freighters count
  towards it like anyone else; with yield on, a station full of them still
  makes room for a person. And the atom ceiling: ship names really do become
  atoms, that really is irreversible, so every name comes from a pool whose
  size is known at compile time.
  """

  use DynamicSupervisor

  alias Station.Cargo
  alias Station.Dispatcher
  alias Station.Events
  alias Station.FreighterLine
  alias Station.OpsPanel
  alias Station.Ship
  alias Station.ShipNames

  # Where every ship publishes its snapshot, because nothing may read a ship
  # with a call: a ship sleeps while it loads, and a caller would sleep with it.
  @status :station_ship_status

  @type dock_error :: :at_capacity | :no_names

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if :ets.whereis(@status) == :undefined do
      :ets.new(@status, [:set, :public, :named_table, read_concurrency: true])
    end

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec status_table() :: atom()
  def status_table, do: @status

  @doc """
  Docks a new ship under a generated name with a random cargo type.

  Returns the registered process name, which is the string the visitor then
  hunts for on the big screen.
  """
  @spec dock() :: {:ok, atom()} | {:error, dock_error()}
  def dock do
    with :ok <- check_capacity(),
         {:ok, slug} <- ShipNames.pick(list()) do
      start(ShipNames.to_process_name(slug), Enum.random(Cargo.types()))
    end
  end

  @spec capacity() :: pos_integer()
  def capacity, do: Application.fetch_env!(:station, :max_ships)

  @doc "Visitors docked. Freighters are counted by `occupied/0`."
  @spec count() :: non_neg_integer()
  def count, do: DynamicSupervisor.count_children(__MODULE__).active

  @doc "Every ship on the screen, visitor or freighter."
  @spec occupied() :: non_neg_integer()
  def occupied, do: count() + FreighterLine.count()

  @spec full?() :: boolean()
  def full?, do: occupied() >= capacity()

  @doc "Registered names of every docked ship, oldest first."
  @spec list() :: [atom()]
  def list do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn {_, pid, _, _} ->
      case Process.info(pid, :registered_name) do
        {:registered_name, name} when is_atom(name) -> [name]
        _ -> []
      end
    end)
    |> Enum.reverse()
  end

  @doc "Ops kicking one ship off the station."
  @spec remove(atom()) :: :ok
  def remove(name) do
    case Process.whereis(name) do
      nil ->
        :ok

      pid ->
        Events.emit(:ops, "#{name} REMOVED BY OPS", :warning)
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok
    end
  end

  @spec clear() :: :ok
  def clear do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(__MODULE__) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end

    :ok
  end

  # A full station turns a visitor away - unless the berths are held by
  # freighters and ops said they yield, in which case one goes home right now
  # rather than on the dispatcher's next tick, so this visitor gets its berth.
  defp check_capacity do
    cond do
      not full?() -> :ok
      count() >= capacity() -> {:error, :at_capacity}
      OpsPanel.yield_to_visitors?() -> Dispatcher.make_room()
      true -> {:error, :at_capacity}
    end
  end

  # Two phones can pick the same free name in the same instant; the second
  # start fails on the registered name and tries again with a fresh draw.
  defp start(name, cargo_type, attempts \\ 3) do
    spec = {Ship, name: name, cargo_type: cargo_type}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, _pid} -> {:ok, name}
      {:error, {:already_started, _}} when attempts > 1 -> retry(cargo_type, attempts - 1)
      {:error, {:already_started, _}} -> {:error, :no_names}
      {:error, reason} -> {:error, reason}
    end
  end

  defp retry(cargo_type, attempts) do
    case ShipNames.pick(list()) do
      {:ok, slug} -> start(ShipNames.to_process_name(slug), cargo_type, attempts)
      :error -> {:error, :no_names}
    end
  end
end
