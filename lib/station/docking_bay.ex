defmodule Station.DockingBay do
  @moduledoc """
  Where visitors' ships live: a DynamicSupervisor whose children are the people
  standing in front of the booth.

  It owns the two decisions that keep that safe. The live ship cap is set for
  the human eye, not for the runtime - twenty five nodes is already a dense
  tree on a television, and the BEAM would carry twenty five thousand. And the
  atom ceiling: ship names really do become atoms, that really is irreversible,
  so past a configured budget new visitors get a name from a fixed pool instead
  of one derived from what they typed.
  """

  use DynamicSupervisor

  alias Station.Events
  alias Station.Ship
  alias Station.ShipNames

  @minted :station_ship_atoms
  @fallback_key {__MODULE__, :fallback_seq}

  @type dock_error :: :at_capacity | :name_taken | :too_short | :blocked | :invalid

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if :ets.whereis(@minted) == :undefined do
      :ets.new(@minted, [:set, :public, :named_table, read_concurrency: true])
    end

    :persistent_term.put(@fallback_key, :atomics.new(1, signed: false))
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Registers a ship and starts it.

  Returns the registered process name, which is the string the visitor then
  hunts for on the big screen.
  """
  @spec dock(String.t(), String.t()) :: {:ok, atom()} | {:error, dock_error()}
  def dock(raw_name, cargo_type) do
    with :ok <- check_capacity(),
         :ok <- check_cargo(cargo_type),
         {:ok, slug} <- ShipNames.normalize(raw_name),
         {:ok, name} <- claim(slug) do
      start(name, cargo_type)
    end
  end

  @spec capacity() :: pos_integer()
  def capacity, do: Application.fetch_env!(:station, :max_ships)

  @spec count() :: non_neg_integer()
  def count, do: DynamicSupervisor.count_children(__MODULE__).active

  @spec full?() :: boolean()
  def full?, do: count() >= capacity()

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

  @doc "Ops' last line of defence against a name that got through the filter."
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

  @doc """
  How many atoms this station has minted from visitor input, against its budget.

  Counted exactly, name by name, rather than inferred from the global atom
  count - the VM mints atoms for its own reasons all the time and we would end
  up quietly handing out fallback names because ExUnit compiled a module.
  """
  @spec atom_budget() :: %{used: non_neg_integer(), budget: pos_integer()}
  def atom_budget, do: %{used: :ets.info(@minted, :size), budget: max_ship_atoms()}

  defp check_capacity, do: if(full?(), do: {:error, :at_capacity}, else: :ok)

  defp check_cargo(type),
    do: if(Station.Cargo.valid_type?(type), do: :ok, else: {:error, :invalid})

  # Past the atom budget we stop turning input into atoms and hand out a name
  # from a fixed pool instead. A name that was already minted still works, so a
  # visitor coming back on day two keeps the ship they named on day one.
  defp claim(slug) do
    name =
      case existing(slug) do
        {:ok, name} -> name
        :error -> mint_or_fallback(slug)
      end

    if Process.whereis(name), do: {:error, :name_taken}, else: {:ok, name}
  end

  defp existing(slug) do
    name = String.to_existing_atom(ShipNames.prefix() <> slug)
    if :ets.member(@minted, name), do: {:ok, name}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp mint_or_fallback(slug) do
    if atom_budget().used < max_ship_atoms() do
      name = ShipNames.to_process_name(slug)
      :ets.insert_new(@minted, {name})
      name
    else
      ShipNames.to_process_name(ShipNames.generated(next_fallback()))
    end
  end

  defp start(name, cargo_type) do
    spec = {Ship, name: name, cargo_type: cargo_type}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, _pid} -> {:ok, name}
      {:error, {:already_started, _}} -> {:error, :name_taken}
      {:error, reason} -> {:error, reason}
    end
  end

  defp next_fallback do
    ref = :persistent_term.get(@fallback_key)
    :atomics.add_get(ref, 1, 1)
  end

  defp max_ship_atoms, do: Application.fetch_env!(:station, :max_ship_atoms)
end
