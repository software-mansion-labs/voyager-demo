defmodule StationWeb.NotFound do
  @moduledoc """
  Raised when the ops panel is asked for under the wrong path segment.

  A 404 rather than a 403 on purpose: someone poking at the URL should not learn
  that there is anything behind it.
  """

  defexception message: "not found", plug_status: 404
end
