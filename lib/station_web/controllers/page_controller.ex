defmodule StationWeb.PageController do
  use StationWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
