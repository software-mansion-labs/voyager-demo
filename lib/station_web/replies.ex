defmodule StationWeb.Replies do
  @moduledoc """
  Pipe friendly returns for LiveView callbacks, so a callback reads as one
  pipeline instead of a tuple wrapped around one.
  """

  @spec ok(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def ok(socket), do: {:ok, socket}

  @spec noreply(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def noreply(socket), do: {:noreply, socket}
end
