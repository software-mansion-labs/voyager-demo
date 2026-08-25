defmodule Mix.Tasks.Station.Calibrate do
  @shortdoc "Measures inspection cost per cargo type and the warehouse ceiling"

  @moduledoc """
  Prints what a single container actually costs on this machine.

  Run it on the box that will run the booth, on the first morning. It measures
  the inspection cost per cargo type and turns that into the number the demo
  really depends on: how many containers per second one warehouse process can
  absorb before its message queue starts climbing.

      mix station.calibrate

  Compare that ceiling against the offered load printed underneath. If the
  station cannot be pushed over the line by a realistic crowd, raise
  `:inspection_rounds`; if it saturates with nobody in front of it, lower them.
  """

  use Mix.Task

  alias Station.Cargo

  @samples 20

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:crypto)

    IO.puts("\n  inspection cost per container\n")
    IO.puts("  cargo         size        cost      warehouse ceiling")
    IO.puts("  " <> String.duplicate("-", 54))

    costs =
      for type <- Cargo.types() do
        ms = measure(type)
        bytes = Cargo.container_bytes(type)

        IO.puts(
          "  #{pad(type, 12)}  #{pad(format_bytes(bytes), 10)}  #{pad(:erlang.float_to_binary(ms, decimals: 2) <> " ms", 8)}  #{round(1000 / ms)}/s"
        )

        {type, ms}
      end

    lookup = Map.new(costs)
    average = Enum.reduce(Cargo.weighted_types(), 0.0, fn {t, w}, acc -> acc + w * lookup[t] end)

    IO.puts(
      "\n  offered load at each traffic level (background cargo mix, #{Float.round(average, 2)} ms avg)\n"
    )

    for {level, %{freighters: count, interval_ms: interval}} <- Station.TrafficControl.levels() do
      # send_after jitters between interval and 2 * interval, so 1.5x on average.
      per_second = count / (interval * 1.5 / 1000)
      load = per_second * average / 1000 * 100

      IO.puts(
        "  #{pad(to_string(level), 12)}  #{pad(Float.round(per_second, 1) |> to_string() |> Kernel.<>("/s"), 10)}  #{Float.round(load, 1)}% of one warehouse"
      )
    end

    visitors = Application.fetch_env!(:station, :max_ships)
    rate = Application.fetch_env!(:station, :transfer_limits)[:per_second]
    crowd = visitors * rate * average / 1000 * 100

    IO.puts("""

      a full house of #{visitors} ships clicking flat out adds #{Float.round(crowd, 1)}%.

      Above 100% the warehouse queue climbs and numer 5.1 works. Well below it,
      raise :inspection_rounds in config/config.exs.
    """)
  end

  defp measure(type) do
    [container] = Cargo.build_hold(type, 1)
    Cargo.inspect_container(container)

    {us, _} =
      :timer.tc(fn ->
        Enum.each(1..@samples, fn _ -> Cargo.inspect_container(container) end)
      end)

    us / @samples / 1000
  end

  defp pad(value, width), do: String.pad_trailing(to_string(value), width)

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{div(bytes, 1024)} KB"
end
