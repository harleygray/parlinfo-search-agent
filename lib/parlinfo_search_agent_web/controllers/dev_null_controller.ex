defmodule ParlInfoSearchAgentWeb.DevNullController do
  use ParlInfoSearchAgentWeb, :controller

  def index(conn, _params), do: json(conn, %{})
end
