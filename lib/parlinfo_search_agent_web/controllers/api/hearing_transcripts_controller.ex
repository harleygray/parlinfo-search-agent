defmodule ParlInfoSearchAgentWeb.Api.HearingTranscriptsController do
  use ParlInfoSearchAgentWeb, :controller

  alias ParlInfoSearchAgent.{Items, Repo}
  alias ParlInfoSearchAgent.Items.HearingTranscript

  def index(conn, params) do
    %{items: items, total: total, page: page, per_page: per_page} =
      Items.list_items(Map.put(params, "dataset", "hearing_transcripts"))

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

    items = Items.get_latest(limit, "hearing_transcripts")
    json(conn, %{items: Enum.map(items, &item_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(HearingTranscript, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})

      item ->
        json(conn, %{item: item_json(item)})
    end
  end

  defp item_json(%HearingTranscript{} = item) do
    %{
      id: item.id,
      parlinfo_ids: item.parlinfo_ids,
      title: item.title,
      date_tabled: item.date_tabled,
      committee_name: item.committee_name,
      pdf_url: item.pdf_url,
      parlinfo_permalink: item.parlinfo_permalink
    }
  end
end
