defmodule StationWeb.StationComponents do
  @moduledoc """
  The small shared pieces of the station's chrome: readouts, gauges and the
  handful of formatters that keep numbers the same width everywhere.
  """

  use Phoenix.Component

  @doc "A labelled number in the station's readout style."
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :string, default: "text-base-content"
  attr :hint, :string, default: nil
  attr :class, :any, default: nil

  def readout(assigns) do
    ~H"""
    <div class={["pixel-panel flex flex-col gap-1 p-3", @class]}>
      <span class="font-pixel text-[0.5625rem] text-base-content/50">{@label}</span>
      <span class={["font-pixel text-sm tabular-nums", @tone]}>{@value}</span>
      <span :if={@hint} class="font-mono text-[0.625rem] text-base-content/40">{@hint}</span>
    </div>
    """
  end

  @doc """
  A chunky segmented bar. Pixels, not a gradient: it fills one whole block at a
  time so it reads from across the aisle.
  """
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :segments, :integer, default: 20
  attr :tone, :string, default: "bg-primary"
  attr :class, :any, default: nil

  def meter(assigns) do
    filled =
      assigns.max
      |> then(&if(&1 <= 0, do: 0, else: assigns.value / &1))
      |> min(1.0)
      |> Kernel.*(assigns.segments)
      |> round()

    assigns = assign(assigns, :filled, filled)

    ~H"""
    <div class={["flex gap-[2px]", @class]} role="meter" aria-valuenow={@value} aria-valuemax={@max}>
      <span
        :for={index <- 1..@segments}
        class={[
          "h-3 flex-1",
          if(index <= @filled, do: @tone, else: "bg-base-300")
        ]}
      />
    </div>
    """
  end

  @doc "Bytes as something a person can read at a glance."
  @spec format_bytes(number()) :: String.t()
  def format_bytes(bytes) when bytes < 1_024, do: "#{round(bytes)} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"

  def format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  @doc "Thousands separated, so a six figure queue is legible on a television."
  @spec format_count(integer()) :: String.t()
  def format_count(number) do
    number
    |> abs()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
    |> then(&if(number < 0, do: "-" <> &1, else: &1))
  end

  @doc "Short relative time, for the leaderboard's last delivery column."
  @spec format_ago(integer() | nil) :: String.t()
  def format_ago(nil), do: "-"

  def format_ago(unix_seconds) do
    case System.system_time(:second) - unix_seconds do
      seconds when seconds < 60 -> "#{seconds}s"
      seconds when seconds < 3_600 -> "#{div(seconds, 60)}m"
      seconds when seconds < 86_400 -> "#{div(seconds, 3_600)}h"
      seconds -> "#{div(seconds, 86_400)}d"
    end
  end
end
