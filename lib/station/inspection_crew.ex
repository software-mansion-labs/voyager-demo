defmodule Station.InspectionCrew do
  @moduledoc """
  The pool of inspectors the warehouse delegates checksums to.

  Empty in `:single_clerk` mode and populated in `:inspection_crew` mode, so
  flipping the switch in /ops makes the process count jump in Voyager while the
  warehouse queue drains. That visible jump is the point - the supervisor node
  stays in the tree either way, only its child counter moves.
  """

  use DynamicSupervisor

  alias Station.Inspector

  # The crew is published here as well as held by the supervisor, because the
  # warehouse asks who is on shift once per container and must never wait on a
  # message to find out. Writing a persistent term is expensive; staffing
  # happens when ops presses a button, so that cost lands where nobody is
  # counting microseconds.
  @term_key {__MODULE__, :on_shift}

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Default pool size: one inspector per scheduler."
  @spec default_size() :: pos_integer()
  def default_size do
    Application.get_env(:station, :inspectors) || System.schedulers_online()
  end

  @doc "Registered names of the inspectors currently on shift."
  @spec workers() :: [atom()]
  def workers do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn {_, pid, _, _} ->
      case Process.info(pid, :registered_name) do
        {:registered_name, name} when is_atom(name) -> [name]
        _ -> []
      end
    end)
    |> Enum.sort()
  end

  @doc """
  The crew as a tuple, readable without sending anyone a message.

  Empty when the crew is off shift, which is also what the warehouse falls back
  on before ops has touched anything.
  """
  @spec on_shift() :: tuple()
  def on_shift, do: :persistent_term.get(@term_key, {})

  @spec size() :: non_neg_integer()
  def size, do: DynamicSupervisor.count_children(__MODULE__).active

  @doc "Puts `count` inspectors on shift, replacing whoever is there now."
  @spec staff(non_neg_integer()) :: :ok
  def staff(count) do
    dismiss()

    for n <- 1..count//1 do
      DynamicSupervisor.start_child(__MODULE__, {Inspector, name: worker_name(n)})
    end

    publish()
  end

  @spec dismiss() :: :ok
  def dismiss do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(__MODULE__) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end

    publish()
  end

  @doc "Hands one container to the next inspector in the rotation."
  @spec dispatch(atom(), String.t(), Station.Cargo.container()) :: :ok
  def dispatch(inspector, ship, container) do
    GenServer.cast(inspector, {:inspect, ship, container})
  end

  defp publish, do: :persistent_term.put(@term_key, List.to_tuple(workers()))

  defp worker_name(n), do: :"inspector_#{String.pad_leading(to_string(n), 2, "0")}"
end
