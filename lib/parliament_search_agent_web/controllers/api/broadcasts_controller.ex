defmodule ParliamentSearchAgentWeb.Api.BroadcastsController do
  use ParliamentSearchAgentWeb, :controller

  alias ParliamentSearchAgent.{Items, Repo}
  alias ParliamentSearchAgent.Items.Broadcast

  def index(conn, params) do
    %{items: items, total: total, page: page, per_page: per_page} =
      Items.list_items(Map.put(params, "dataset", "broadcasts"))

    json(
      conn,
      Jason.OrderedObject.new([
        {"items", Enum.map(items, &item_json/1)},
        {"page", page},
        {"per_page", per_page},
        {"total", total}
      ])
    )
  end

  def latest(conn, params) do
    limit =
      case Integer.parse(to_string(params["limit"] || "20")) do
        {n, _} -> min(max(n, 1), 100)
        :error -> 20
      end

    items = Items.get_latest(limit, "broadcasts")
    json(conn, %{items: Enum.map(items, &item_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(Broadcast, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})

      item ->
        json(conn, %{item: item_json(item)})
    end
  end

  defp item_json(%Broadcast{} = item) do
    %{
      id: item.id,
      parlview_id: item.parlview_id,
      title: item.title,
      chamber: item.chamber,
      is_live: item.is_live,
      source_url: item.source_url,
      start_time: item.start_time,
      duration: item.duration
    }
  end
end
