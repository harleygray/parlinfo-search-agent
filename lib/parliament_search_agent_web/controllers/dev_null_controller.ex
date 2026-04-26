defmodule ParliamentSearchAgentWeb.DevNullController do
  use ParliamentSearchAgentWeb, :controller

  def index(conn, _params), do: json(conn, %{})
end
