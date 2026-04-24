defmodule ParlInfoSearchAgentWeb.PageController do
  use ParlInfoSearchAgentWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
