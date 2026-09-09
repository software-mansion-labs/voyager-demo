defmodule StationWeb.PixelCanvas do
  @moduledoc """
  A grid of coloured pixels and the few strokes the station's art is drawn in.

  A canvas is a map of `{x, y}` to a tone atom. `runs/1` turns it into
  run-length rows - `{x, y, width, tone}` - so a plate forty pixels wide is one
  SVG rectangle. Separate from `StationWeb.StationArt` because that module
  draws at compile time, and a module cannot call its own functions while it
  is still being compiled.
  """

  @type tone :: atom()
  @type canvas :: %{{integer(), integer()} => tone()}
  @type run :: {integer(), integer(), pos_integer(), tone()}

  @spec new() :: canvas()
  def new, do: %{}

  @spec rect(canvas(), integer(), integer(), integer(), integer(), tone()) :: canvas()
  def rect(canvas, x, y, w, h, tone) do
    for px <- x..(x + w - 1)//1, py <- y..(y + h - 1)//1, reduce: canvas do
      canvas -> Map.put(canvas, {px, py}, tone)
    end
  end

  @spec clear(canvas(), [{integer(), integer()}]) :: canvas()
  def clear(canvas, points), do: Map.drop(canvas, points)

  @doc "A solar panel: an edge, a face, and a cell line every six pixels."
  @spec panel(canvas(), integer(), integer(), integer(), integer()) :: canvas()
  def panel(canvas, x, y, w, h) do
    canvas = canvas |> rect(x, y, w, h, :panel_edge) |> rect(x + 1, y + 1, w - 2, h - 2, :panel)

    (x + 6)..(x + w - 2)//6
    |> Enum.reduce(canvas, fn line, canvas -> rect(canvas, line, y + 1, 1, h - 2, :panel_line) end)
  end

  @doc "A five pixel `>` on a two pixel pillar, centred on `y`."
  @spec chevron(canvas(), integer(), integer()) :: canvas()
  def chevron(canvas, x, y) do
    canvas
    |> rect(x, y - 2, 1, 1, :chevron)
    |> rect(x + 1, y - 1, 1, 1, :chevron)
    |> rect(x + 1, y, 1, 1, :chevron)
    |> rect(x + 1, y + 1, 1, 1, :chevron)
    |> rect(x, y + 2, 1, 1, :chevron)
  end

  @doc "Run-length rows: consecutive pixels of one tone become one rectangle."
  @spec runs(canvas()) :: [run()]
  def runs(canvas) do
    canvas
    |> Enum.group_by(fn {{_x, y}, _tone} -> y end)
    |> Enum.sort()
    |> Enum.flat_map(fn {y, pixels} ->
      pixels
      |> Enum.map(fn {{x, _y}, tone} -> {x, tone} end)
      |> Enum.sort()
      |> Enum.reduce([], fn
        {x, tone}, [{rx, ry, rw, tone} | rest] when rx + rw == x ->
          [{rx, ry, rw + 1, tone} | rest]

        {x, tone}, acc ->
          [{x, y, 1, tone} | acc]
      end)
      |> Enum.reverse()
    end)
  end
end
