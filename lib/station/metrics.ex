defmodule Station.Metrics do
  @moduledoc """
  Shared counters, readable without sending the warehouse a message.

  This matters: the warehouse is the process the demo deliberately congests. If
  the dashboards asked it for its own numbers they would queue up behind the
  cargo they are trying to measure. `:counters` are lock-free and live outside
  any process, so reading them costs the warehouse nothing.
  """

  @keys [
    :accepted,
    :inspected,
    :dropped,
    :collected,
    :stored,
    :stored_bytes,
    :ships_docked,
    :ships_undocked,
    :throttled,
    :queue,
    :warehouse_memory,
    :warehouse_reductions,
    :run_queue,
    :process_count,
    :atom_count
  ]

  @term_key {__MODULE__, :ref}

  @type key ::
          :accepted
          | :inspected
          | :dropped
          | :collected
          | :stored
          | :stored_bytes
          | :ships_docked
          | :ships_undocked
          | :throttled
          | :queue
          | :warehouse_memory
          | :warehouse_reductions
          | :run_queue
          | :process_count
          | :atom_count

  @doc "Creates the counter array. Called once, from the application supervisor."
  @spec setup() :: :ok
  def setup do
    :persistent_term.put(@term_key, :counters.new(length(@keys), [:write_concurrency]))
  end

  @spec add(key(), integer()) :: :ok
  def add(key, amount), do: :counters.add(ref(), index(key), amount)

  @spec sub(key(), integer()) :: :ok
  def sub(key, amount), do: :counters.sub(ref(), index(key), amount)

  @doc "Sets a gauge. Counters are `add/2`, sampled values are `put/2`."
  @spec put(key(), integer()) :: :ok
  def put(key, value), do: :counters.put(ref(), index(key), value)

  @spec get(key()) :: integer()
  def get(key), do: :counters.get(ref(), index(key))

  @spec all() :: %{key() => integer()}
  def all, do: Map.new(@keys, &{&1, get(&1)})

  @spec reset() :: :ok
  def reset, do: Enum.each(@keys, &:counters.put(ref(), index(&1), 0))

  defp ref, do: :persistent_term.get(@term_key)

  for {key, index} <- Enum.with_index(@keys, 1) do
    defp index(unquote(key)), do: unquote(index)
  end
end
