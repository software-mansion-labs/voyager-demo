defmodule Station.Booth do
  @moduledoc """
  Where to tell a visitor's phone to go.

  The booth has no domain and no certificate. The station runs on a laptop on
  its own hotspot, and the address a phone can reach is whatever that laptop was
  handed on that network this morning - which is exactly the sort of thing that
  gets printed on a card the night before and is wrong by the time the doors
  open. So the television reads it off the running machine instead.

  `STATION_DOCK_URL` overrides everything, for the day the address is not
  guessable from the outside.
  """

  @doc "The URL behind the QR code on the television."
  @spec dock_url() :: String.t()
  def dock_url do
    System.get_env("STATION_DOCK_URL") || served_address() || StationWeb.Endpoint.url()
  end

  # Only worth advertising the address of an interface the station is actually
  # listening on. Bound to loopback - which is every laptop that is not the
  # booth - the machine's wifi address is a QR code that leads nowhere.
  defp served_address do
    case StationWeb.Endpoint.config(:http)[:ip] do
      {127, _, _, _} -> nil
      {0, 0, 0, 0, 0, 0, 0, 1} -> nil
      nil -> nil
      _ -> from_interfaces()
    end
  end

  defp from_interfaces do
    case lan_address() do
      nil -> nil
      address -> "http://#{:inet.ntoa(address)}:#{port()}"
    end
  end

  # The first address on an interface that is up, running and not loopback. On a
  # laptop serving its own hotspot there is one such address and it is the right
  # one; where there are several - wifi and ethernet both live - the first is a
  # guess, and STATION_DOCK_URL is the answer to a bad guess.
  defp lan_address do
    {:ok, interfaces} = :inet.getifaddrs()

    Enum.find_value(interfaces, fn {_name, options} ->
      flags = Keyword.get(options, :flags, [])

      if :up in flags and :running in flags and :loopback not in flags do
        options
        |> Keyword.get_values(:addr)
        |> Enum.find(&match?({_, _, _, _}, &1))
      end
    end)
  end

  defp port do
    StationWeb.Endpoint.config(:http)[:port] || 4000
  end
end
