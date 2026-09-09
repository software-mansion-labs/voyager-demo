defmodule Station.ShipNames do
  @moduledoc """
  The names ships are registered under.

  Ship names deliberately become atoms - that is the lesson the booth tells -
  and a visitor is never asked for one. Every name is drawn from the fixed pool
  below, so however many people scan the code over two days the station mints
  at most #{20 * 25} atoms, and a returning name is the same atom it was.

  Nothing here takes visitor input, and nothing should start to: the pool is
  the whole safety story. The registered name of a ship is `ship_` and a slug
  from `pool/0`.
  """

  @prefix "ship_"

  @adjectives ~w(
    amber bold brass cobalt crimson dusty ember frosty gilded hollow indigo
    iron jade lunar misty nimble onyx pale quiet rusty
  )

  @nouns ~w(
    albatross badger comet drifter falcon gecko heron ibis jackal kestrel
    lantern marlin nomad otter pilgrim quasar raven sparrow tern umbra
    vagrant walrus yeti zephyr wren
  )

  @pool for adjective <- @adjectives, noun <- @nouns, do: "#{adjective}_#{noun}"

  @doc "Every slug a ship can be called. Finite, on purpose."
  @spec pool() :: [String.t()]
  def pool, do: @pool

  @spec pool_size() :: pos_integer()
  def pool_size, do: length(@pool)

  @doc """
  A slug from the pool that is not in `taken`.

  Random rather than sequential so two phones docking together do not read as
  `_1` and `_2` on the big screen, and so a fresh ship after undocking is
  usually a fresh name. Returns `:error` only if the whole pool is in use,
  which the live ship cap keeps far out of reach.
  """
  @spec pick(Enumerable.t()) :: {:ok, String.t()} | :error
  def pick(taken) do
    taken = MapSet.new(taken, &to_slug/1)

    case Enum.reject(@pool, &MapSet.member?(taken, &1)) do
      [] -> :error
      free -> {:ok, Enum.random(free)}
    end
  end

  @doc "The registered process name for a slug."
  @spec to_process_name(String.t()) :: atom()
  def to_process_name(slug) when slug in @pool do
    # Deliberate: the growing atom table is part of the demo. Bounded by the
    # guard above - only a slug from the pool ever becomes an atom.
    String.to_atom(@prefix <> slug)
  end

  @spec prefix() :: String.t()
  def prefix, do: @prefix

  @doc "Strips the `ship_` prefix back off for display."
  @spec to_slug(atom() | String.t()) :: String.t()
  def to_slug(name) when is_atom(name), do: name |> Atom.to_string() |> to_slug()
  def to_slug(@prefix <> slug), do: slug
  def to_slug(name) when is_binary(name), do: name
end
