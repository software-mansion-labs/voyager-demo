defmodule Station.ShipNames do
  @moduledoc """
  Turns whatever a visitor typed into a registered process name.

  Ship names deliberately become atoms - that is the lesson the booth tells - so
  everything here exists to keep that decision safe: a fixed character set, a
  length cap, a profanity filter and a hard ceiling on how many distinct atoms
  the station will ever create. Past the ceiling visitors get a generated name.
  """

  @max_length 24
  @min_length 2
  @prefix "ship_"

  # Coarse on purpose. The real last line of defence is `Remove ship` in /ops.
  @blocked ~w(
    fuck shit cunt bitch dick cock whore slut nigger nigga faggot rape retard
    kurwa chuj huj pizda jebac jebać pierdol pierdolic pierdolić skurwysyn
    cipa dupa spierdalaj wypierdalaj zjeb debil szmata pedal pedał
  )

  # NFD splits accents off, but a handful of European letters are not accented
  # forms of anything and would otherwise turn into underscores. Polish names
  # are half the room, so at minimum this has to get "Żółw" right.
  @transliterations %{
    "ł" => "l",
    "ø" => "o",
    "đ" => "d",
    "ð" => "d",
    "æ" => "ae",
    "œ" => "oe",
    "ß" => "ss",
    "þ" => "th"
  }

  @generated_prefixes ~w(
    aurora borealis cobalt drifter ember falcon granite horizon indigo juniper
    kestrel lantern meridian nomad obsidian pilgrim quasar ranger solstice tundra
  )

  @doc """
  Normalises a raw name into a slug, or returns why it was rejected.

  Returns `{:ok, slug}`, `{:error, reason}`.
  """
  @spec normalize(term()) :: {:ok, String.t()} | {:error, atom()}
  def normalize(raw) when is_binary(raw) do
    slug =
      raw
      |> String.downcase()
      |> transliterate()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")
      |> String.slice(0, @max_length)
      |> String.trim("_")

    cond do
      String.length(slug) < @min_length -> {:error, :too_short}
      blocked?(slug) -> {:error, :blocked}
      true -> {:ok, slug}
    end
  end

  def normalize(_), do: {:error, :invalid}

  @doc "The registered process name for a slug."
  @spec to_process_name(String.t()) :: atom()
  def to_process_name(slug) do
    # Deliberate: the growing atom table is part of the demo. Bounded by the
    # charset, the length cap and the ceiling enforced in `Station.DockingBay`.
    String.to_atom(@prefix <> slug)
  end

  @spec prefix() :: String.t()
  def prefix, do: @prefix

  @doc "Strips the `ship_` prefix back off for display."
  @spec to_slug(atom() | String.t()) :: String.t()
  def to_slug(name) when is_atom(name), do: name |> Atom.to_string() |> to_slug()
  def to_slug(@prefix <> slug), do: slug
  def to_slug(name) when is_binary(name), do: name

  @generated_suffixes 25

  @doc """
  A generated fallback name, used once the atom ceiling is reached.

  Drawn from a fixed pool of #{length(@generated_prefixes) * 25} combinations, so
  no matter how many visitors hit the fallback the atom table stops growing. The
  live ship cap is well under that, so a reused name is always free by then.
  """
  @spec generated(non_neg_integer()) :: String.t()
  def generated(seq) do
    prefix = Enum.at(@generated_prefixes, rem(seq, length(@generated_prefixes)))
    suffix = rem(div(seq, length(@generated_prefixes)), @generated_suffixes) + 1
    "#{prefix}_#{suffix}"
  end

  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  defp transliterate(text) do
    String.replace(text, Map.keys(@transliterations), &Map.fetch!(@transliterations, &1))
  end

  defp blocked?(slug) do
    stripped = String.replace(slug, "_", "")
    Enum.any?(@blocked, &String.contains?(stripped, &1))
  end
end
