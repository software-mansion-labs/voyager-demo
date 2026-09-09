defmodule Station.FreighterLine do
  @moduledoc """
  The producers: simulated visitors, as many as ops asks for.

  Zero by default. An empty room is a station at zero, and this is the switch
  that says otherwise when the aisle is quiet and the screens need traffic.
  """

  use DynamicSupervisor

  alias Station.Freighter

  # Where every freighter publishes its snapshot, for the same reason ships do:
  # the television reads it without sending anybody a message.
  @status :station_freighter_status

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if :ets.whereis(@status) == :undefined do
      :ets.new(@status, [:set, :public, :named_table, read_concurrency: true])
    end

    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 100)
  end

  @spec status_table() :: atom()
  def status_table, do: @status

  @spec count() :: non_neg_integer()
  def count, do: DynamicSupervisor.count_children(__MODULE__).active

  @doc "Registered names of every freighter on duty, oldest first."
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

  @doc "Snapshots of every freighter, for the television."
  @spec statuses() :: [map()]
  def statuses do
    for name <- list(),
        status = Freighter.status(name),
        status != {:error, :gone},
        do: status
  end
end
