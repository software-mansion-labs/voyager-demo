defmodule Station.Hangar do
  @moduledoc """
  Where a ship waits while its crew is offline.

  A cockpit that goes dark - phone locked, tab closed, wifi gone - must not
  hold a berth: the ship undocks and frees the screen for the next visitor.
  But the visitor is usually still standing there, and coming back to a fresh
  name and a zeroed counter would feel like the station forgot them. So the
  ship leaves what matters here on its way out - name, cargo type, how much
  was aboard and delivered - and the next scan of the same session docks it
  again from these notes.

  Second level of the persistence story the booth tells: this table outlives
  the ship's process. It does not outlive the node, and it does not need to -
  a parked ship is forgotten after `:ship_ttl_ms`, the same silence that ends
  a docked one. The hold itself is not kept, only its count; cargo is random
  bytes and is rebuilt on the way back in, so a parked machinery hauler costs
  a few words here rather than megabytes.
  """

  use GenServer

  @table :station_hangar

  @type parked :: %{
          slug: String.t(),
          cargo_type: String.t(),
          hold_count: non_neg_integer(),
          delivered: non_neg_integer(),
          refills: non_neg_integer(),
          parked_at: integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec table() :: atom()
  def table, do: @table

  @doc "Leaves a ship's notes behind. Called from the ship's own process as it stops."
  @spec park(map()) :: :ok
  def park(state) do
    sweep()

    parked = %{
      slug: state.slug,
      cargo_type: state.cargo_type,
      hold_count: state.hold_count,
      delivered: state.delivered,
      refills: state.refills,
      parked_at: now_ms()
    }

    :ets.insert(@table, {state.slug, parked})
    :ok
  end

  @doc "Takes a parked ship's notes back out, if they are still fresh."
  @spec take(String.t()) :: {:ok, parked()} | :error
  def take(slug) do
    case :ets.take(@table, slug) do
      [{^slug, parked}] -> if fresh?(parked), do: {:ok, parked}, else: :error
      [] -> :error
    end
  end

  @spec parked?(String.t() | nil) :: boolean()
  def parked?(nil), do: false

  def parked?(slug) do
    case :ets.lookup(@table, slug) do
      [{^slug, parked}] -> fresh?(parked)
      [] -> false
    end
  end

  @doc "Forgets a parked ship - the visitor left for real."
  @spec discard(String.t() | nil) :: :ok
  def discard(nil), do: :ok

  def discard(slug) do
    :ets.delete(@table, slug)
    :ok
  end

  @doc """
  Slugs waiting here. The docking bay keeps these out of the name draw, so a
  returning visitor finds their name free and nobody else is handed it while
  they are on the phone.
  """
  @spec slugs() :: [String.t()]
  def slugs do
    sweep()
    :ets.select(@table, [{{:"$1", :_}, [], [:"$1"]}])
  end

  @spec count() :: non_neg_integer()
  def count, do: length(slugs())

  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    {:ok, %{}}
  end

  # Anything parked longer than a docked ship may idle is gone for good.
  defp sweep do
    cutoff = now_ms() - ttl()
    :ets.select_delete(@table, [{{:_, %{parked_at: :"$1"}}, [{:<, :"$1", cutoff}], [true]}])
    :ok
  end

  defp fresh?(%{parked_at: at}), do: now_ms() - at < ttl()

  defp ttl, do: Application.fetch_env!(:station, :ship_ttl_ms)

  defp now_ms, do: System.monotonic_time(:millisecond)
end
