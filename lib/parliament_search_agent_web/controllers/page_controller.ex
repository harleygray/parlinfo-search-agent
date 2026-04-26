defmodule ParliamentSearchAgentWeb.PageController do
  use ParliamentSearchAgentWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
