defmodule Station.Cargo do
  @moduledoc """
  Cargo presets and the inspection work the warehouse performs on every container.

  A container is a plain Elixir term - a list of small binaries - on purpose.
  Terms are copied into the receiver's mailbox, so the memory of a ship visibly
  drops and the memory of the warehouse visibly grows in Voyager. A single large
  refc binary would be shared instead of copied and the whole effect would vanish.
  """

  @type type :: String.t()
  @type container :: %{type: type(), id: pos_integer(), payload: [binary()]}

  @chunk_bytes 32

  @doc "Cargo presets, keyed by the string used in the registration form."
  @spec presets() :: %{type() => map()}
  def presets, do: Application.fetch_env!(:station, :cargo_types)

  @doc """
  Cargo types cheapest first.

  The registration screen reads left to right as the story does - ice, then ore,
  then machinery, then the one that costs twenty times as much to inspect.
  """
  @spec types() :: [type()]
  def types do
    presets()
    |> Enum.sort_by(fn {_type, preset} -> {preset.inspection_rounds, preset.chunks} end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec preset(type()) :: map() | nil
  def preset(type), do: Map.get(presets(), type)

  @spec valid_type?(term()) :: boolean()
  def valid_type?(type), do: is_binary(type) and Map.has_key?(presets(), type)

  @doc "Containers a freshly docked ship carries in its hold."
  @spec hold_size() :: pos_integer()
  def hold_size, do: Application.fetch_env!(:station, :hold_size)

  @doc """
  Builds a hold of `count` containers of the given type.

  Payload bytes are random so the checksum cannot be cached anywhere.
  """
  @spec build_hold(type(), pos_integer()) :: [container()]
  def build_hold(type, count \\ hold_size()) do
    %{chunks: chunks} = preset(type)
    for id <- 1..count, do: %{type: type, id: id, payload: random_payload(chunks)}
  end

  @doc """
  A cargo type for the background fleet, drawn from the configured weights.

  Not uniform on purpose - see `:freighter_cargo_weights` in config.
  """
  @spec random_type() :: type()
  def random_type do
    weights = Application.fetch_env!(:station, :freighter_cargo_weights)
    pick(weights, :rand.uniform(Enum.sum(Keyword.values(weights))))
  end

  @doc "Average inspection weight per background container, for calibration."
  @spec weighted_types() :: [{type(), float()}]
  def weighted_types do
    weights = Application.fetch_env!(:station, :freighter_cargo_weights)
    total = Enum.sum(Keyword.values(weights))
    for {type, weight} <- weights, do: {to_string(type), weight / total}
  end

  @spec container_bytes(type()) :: pos_integer()
  def container_bytes(type) do
    %{chunks: chunks} = preset(type)
    chunks * @chunk_bytes
  end

  @doc """
  The inspection: serialise the container, hash it, then re-hash the digest
  `effective_rounds/1` times.

  The configured rounds are the cost for one lone visitor, and the crowd
  divides them: with N ships docked each container costs a Nth. That keeps two
  promises at once. One visitor saturates most of a clerk - their press is
  visible work. And a room of visitors saturates the same clerk by the same
  margin instead of by twenty five times, so the queue is a story about
  congestion rather than a number that ran away, and the warehouse actually
  absorbs the crowd's cargo - memory visibly fills in minutes, and drains when
  the room quiets down. The per-type ratios survive the division: antimatter
  stays twenty times an ice cube whoever is in the room.
  """
  @spec inspect_container(container()) :: binary()
  def inspect_container(%{type: type, payload: payload}) do
    rounds = effective_rounds(type)

    digest = :crypto.hash(:sha256, :erlang.term_to_binary(payload))
    Enum.reduce(1..rounds, digest, fn _, acc -> :crypto.hash(:sha256, acc) end)
  end

  @doc "What one container of this type costs right now, crowd included."
  @spec effective_rounds(type()) :: pos_integer()
  def effective_rounds(type) do
    %{inspection_rounds: rounds} = preset(type)
    max(div(rounds, crowd()), 1)
  end

  # Docked visitors, from the lock-free counters - this runs once per container
  # inside the very process the demo congests, so it must never send a message.
  defp crowd do
    max(Station.Metrics.get(:ships_docked) - Station.Metrics.get(:ships_undocked), 1)
  end

  defp pick([{type, weight} | rest], roll) do
    if roll <= weight, do: to_string(type), else: pick(rest, roll - weight)
  end

  defp random_payload(chunks) do
    for _ <- 1..chunks, do: :crypto.strong_rand_bytes(@chunk_bytes)
  end
end
