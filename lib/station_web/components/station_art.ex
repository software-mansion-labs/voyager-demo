defmodule StationWeb.StationArt do
  @moduledoc """
  The station's hull, as pixel art.

  Drawn on a 160 by 56 grid at compile time from a handful of primitives -
  rectangles, frames, runs of plating - and rendered as one SVG of run-length
  rectangles, so a plate forty pixels wide is one element rather than forty.
  Every colour is a class, so the palette lives in the stylesheet next to the
  rest of the scene and the beacon and navigation lights can blink from CSS.

  The four windows are where the live data sits: the television overlays the
  intake, inspection, warehouse and outbound panels on the same grid
  coordinates (`window/1`), so the art and the numbers line up whatever size
  the screen is. The hull is one process, `Station.Warehouse`; the windows are
  the stages a container passes through inside it.
  """

  use Phoenix.Component

  import StationWeb.PixelCanvas

  @width 160
  @height 56

  # Window cut-outs, in grid columns: {left, width}. Rows are shared.
  # Sized to their labels: the pixel font on the television runs twelve pixels
  # a character, and the warehouse takes whatever is left.
  @windows %{
    intake: {14, 18},
    inspection: {34, 27},
    warehouse: {63, 59},
    outbound: {124, 22}
  }
  @window_top 16
  @window_height 27

  @doc "Grid size, for anyone placing something on the hull."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: {@width, @height}

  @doc """
  Where a window sits, as CSS percentages of the hull's box.

  Returns `left`, `top`, `width`, `height` strings ready for an inline style.
  """
  @spec window(atom()) :: %{
          left: String.t(),
          top: String.t(),
          width: String.t(),
          height: String.t()
        }
  def window(name) do
    {left, width} = Map.fetch!(@windows, name)
    box(left, @window_top, width, @window_height)
  end

  @doc "Centre of a docking pad, as CSS percentages: `left` and `top`."
  @spec pad(:in | :out) :: %{left: String.t(), top: String.t()}
  def pad(:in), do: %{left: pct(3, @width), top: pct(29, @height)}
  def pad(:out), do: %{left: pct(157, @width), top: pct(29, @height)}

  defp box(x, y, w, h) do
    %{left: pct(x, @width), top: pct(y, @height), width: pct(w, @width), height: pct(h, @height)}
  end

  defp pct(value, of), do: "#{Float.round(value / of * 100, 3)}%"

  # --- the drawing ---------------------------------------------------------

  @rects new()
         |> then(fn canvas ->
           # Mast and dish, dead centre.
           canvas
           |> rect(79, 1, 2, 10, :strut)
           |> rect(79, 0, 2, 1, :beacon)
           |> rect(77, 2, 6, 1, :dish)
           |> rect(75, 3, 10, 1, :dish)
           |> rect(74, 4, 12, 1, :dish)
           |> rect(76, 5, 8, 1, :dish)
           |> rect(78, 6, 4, 1, :dish)
         end)
         # Solar arrays above and below, two panels each side of the mast, on
         # struts down to the hull.
         |> then(fn canvas ->
           Enum.reduce([{18, 4}, {90, 4}, {18, 47}, {90, 47}], canvas, fn {x, y}, canvas ->
             panel(canvas, x, y, 52, 5)
           end)
         end)
         |> rect(42, 9, 2, 4, :strut)
         |> rect(116, 9, 2, 4, :strut)
         |> rect(42, 46, 2, 1, :strut)
         |> rect(116, 46, 2, 1, :strut)
         # The hull: a dark edge, a lit body, stepped corners, wrapped one
         # pixel around the windows and nothing more.
         |> rect(12, 13, 136, 33, :hull_dark)
         |> rect(13, 14, 134, 31, :hull)
         |> clear([{12, 13}, {147, 13}, {12, 45}, {147, 45}])
         # Plating along the top and bottom rows, alternating.
         |> then(fn canvas ->
           13..146//10
           |> Enum.with_index()
           |> Enum.reduce(canvas, fn {x, index}, canvas ->
             tone = if rem(index, 2) == 0, do: :plate, else: :hull
             w = min(10, 147 - x)

             canvas
             |> rect(x, 14, w, 1, tone)
             |> rect(x, 44, w, 1, tone)
           end)
         end)
         # The four windows, each in a one pixel frame.
         |> then(fn canvas ->
           Enum.reduce(@windows, canvas, fn {_name, {x, w}}, canvas ->
             canvas
             |> rect(x - 1, @window_top - 1, w + 2, @window_height + 2, :frame)
             |> rect(x, @window_top, w, @window_height, :window)
           end)
         end)
         # Chevrons on the pillars between windows: the direction of cargo.
         |> chevron(32, 29)
         |> chevron(61, 29)
         |> chevron(122, 29)
         # Docking arms out to a ring on either side.
         |> rect(6, 28, 6, 2, :strut)
         |> rect(148, 28, 6, 2, :strut)
         |> rect(0, 25, 6, 8, :frame)
         |> rect(1, 26, 4, 6, :window)
         |> rect(154, 25, 6, 8, :frame)
         |> rect(155, 26, 4, 6, :window)
         # Navigation lights on the hull corners, blinking in two phases.
         |> rect(13, 14, 1, 1, :nav)
         |> rect(146, 44, 1, 1, :nav)
         |> rect(146, 14, 1, 1, :nav_alt)
         |> rect(13, 44, 1, 1, :nav_alt)
         |> runs()

  attr :class, :any, default: nil

  def hull(assigns) do
    assigns = assigns |> assign(:rects, @rects) |> assign(:viewbox, "0 0 #{@width} #{@height}")

    ~H"""
    <svg
      viewBox={@viewbox}
      class={["pixelated", @class]}
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <rect
        :for={{x, y, w, tone} <- @rects}
        x={x}
        y={y}
        width={w}
        height="1"
        class={"k-#{tone}"}
      />
    </svg>
    """
  end
end
