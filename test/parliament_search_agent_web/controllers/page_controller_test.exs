defmodule ParliamentSearchAgentWeb.PageControllerTest do
  use ParliamentSearchAgentWeb.ConnCase

  test "GET / redirects to LiveView dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Parliament Search Agent"
  end
end
