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

  @spec types() :: [type()]
  def types, do: Map.keys(presets()) |> Enum.sort()

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
  `inspection_rounds` times.

  The first hash scales with the container size, the rounds are a flat per-type
  cost. Together they are the two knobs that decide whether a single click is
  visible in the warehouse reductions.
  """
  @spec inspect_container(container()) :: binary()
  def inspect_container(%{type: type, payload: payload}) do
    %{inspection_rounds: rounds} = preset(type)

    digest = :crypto.hash(:sha256, :erlang.term_to_binary(payload))
    Enum.reduce(1..rounds, digest, fn _, acc -> :crypto.hash(:sha256, acc) end)
  end

  defp pick([{type, weight} | rest], roll) do
    if roll <= weight, do: to_string(type), else: pick(rest, roll - weight)
  end

  defp random_payload(chunks) do
    for _ <- 1..chunks, do: :crypto.strong_rand_bytes(@chunk_bytes)
  end
end
