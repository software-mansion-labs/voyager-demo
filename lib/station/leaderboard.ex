defmodule Station.Leaderboard do
  @moduledoc """
  Owns the `:station_leaderboard` ETS table and its snapshot on disk.

  Third level of the persistence story the booth tells:

      process state  -> dies with the process
      ETS            -> survives the process, dies with the node
      file           -> survives the node

  The table is public so the warehouse can bump counters straight from its own
  process. This module only owns it, snapshots it and hands out reads.
  """

  use GenServer

  require Logger

  @table :station_leaderboard
  @snapshot_every :timer.seconds(30)

  @type row :: %{
          ship: String.t(),
          cargo: String.t(),
          containers: non_neg_integer(),
          last_delivery: integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec table() :: atom()
  def table, do: @table

  @doc "Records a delivery. Called straight from the warehouse process."
  @spec record(String.t(), String.t(), pos_integer()) :: :ok
  def record(ship, cargo, containers \\ 1) do
    now = System.system_time(:second)
    :ets.update_counter(@table, ship, {3, containers}, {ship, cargo, 0, now})
    :ets.update_element(@table, ship, [{2, cargo}, {4, now}])
    :ok
  end

  @doc "Top `limit` ships by containers delivered."
  @spec top(pos_integer()) :: [row()]
  def top(limit \\ 20) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_ship, _cargo, containers, last} -> {-containers, -last} end)
    |> Enum.take(limit)
    |> Enum.map(&to_row/1)
  end

  @spec get(String.t()) :: row() | nil
  def get(ship) do
    case :ets.lookup(@table, ship) do
      [entry] -> to_row(entry)
      [] -> nil
    end
  end

  @spec size() :: non_neg_integer()
  def size, do: :ets.info(@table, :size)

  @spec total_containers() :: non_neg_integer()
  def total_containers do
    :ets.foldl(fn {_s, _c, containers, _l}, acc -> acc + containers end, 0, @table)
  end

  @doc "Clears the table and the snapshot on disk."
  @spec reset() :: :ok
  def reset, do: GenServer.call(__MODULE__, :reset)

  @doc "Writes the snapshot now instead of waiting for the timer."
  @spec snapshot() :: :ok | {:error, term()}
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    path = snapshot_path()
    File.mkdir_p!(Path.dirname(path))

    case :ets.file2tab(String.to_charlist(path)) do
      {:ok, @table} ->
        Logger.info("leaderboard restored from #{path} (#{:ets.info(@table, :size)} ships)")

      {:error, _reason} ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    schedule_snapshot()
    {:ok, %{path: path}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    File.rm(state.path)
    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, write(state.path), state}

  @impl true
  def handle_info(:snapshot, state) do
    write(state.path)
    schedule_snapshot()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    write(state.path)
    :ok
  end

  defp write(path) do
    tmp = path <> ".tmp"

    with :ok <- :ets.tab2file(@table, String.to_charlist(tmp), sync: true),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} = error ->
        Logger.warning("leaderboard snapshot failed: #{inspect(reason)}")
        error
    end
  end

  defp schedule_snapshot, do: Process.send_after(self(), :snapshot, @snapshot_every)

  defp snapshot_path, do: Application.fetch_env!(:station, :leaderboard_path)

  defp to_row({ship, cargo, containers, last_delivery}) do
    %{ship: ship, cargo: cargo, containers: containers, last_delivery: last_delivery}
  end
end
