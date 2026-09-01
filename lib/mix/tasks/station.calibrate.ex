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

    # A ship ships at ramp speed, and the crowd divides the inspection cost, so
    # the offered load per clerk is the same for one racing visitor or thirty.
    rate = 1000 / Application.fetch_env!(:station, :ship_load_ms)
    per_visitor = for {type, ms} <- costs, do: {type, rate * ms / 1000 * 100}

    IO.puts("\n  a room racing flat out, per clerk (crowd divides the cost, so any crowd)\n")

    for {type, load} <- per_visitor do
      IO.puts("  #{pad(type, 12)}  #{Float.round(load, 1)}% of one warehouse")
    end

    IO.puts("""

      Above 100% the warehouse queue climbs and the ops switch matters. Well
      below it, raise :inspection_rounds in config/config.exs. These are the
      one-visitor costs: with N ships docked each container costs a Nth.
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
