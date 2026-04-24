defmodule ParlInfoSearchAgentWeb.Api.BroadcastsControllerTest do
  use ParlInfoSearchAgentWeb.ConnCase, async: false

  alias ParlInfoSearchAgent.Items

  @base_attrs %{
    "parlview_id" => "test-001",
    "title" => "Senate Economics Committee Broadcast",
    "source_url" => "http://parlview.aph.gov.au/mediaPlayer.php?videoID=test-001&action=playMedia"
  }

  defp insert_broadcast(overrides \\ %{}) do
    {:ok, :new, broadcast} = Items.upsert_broadcast(Map.merge(@base_attrs, overrides))
    broadcast
  end

  describe "GET /api/broadcasts" do
    test "returns empty list when no broadcasts exist", %{conn: conn} do
      conn = get(conn, ~p"/api/broadcasts")
      body = json_response(conn, 200)
      assert body["items"] == []
      assert body["total"] == 0
      assert body["page"] == 1
    end

    test "returns inserted broadcasts with correct fields", %{conn: conn} do
      broadcast = insert_broadcast()
      conn = get(conn, ~p"/api/broadcasts")
      body = json_response(conn, 200)
      assert body["total"] == 1
      assert [item] = body["items"]
      assert item["id"] == broadcast.id
      assert item["title"] == "Senate Economics Committee Broadcast"
      assert Map.has_key?(item, "parlview_id")
      assert Map.has_key?(item, "is_live")
      assert Map.has_key?(item, "source_url")
      assert Map.has_key?(item, "start_time")
      assert Map.has_key?(item, "duration")
      refute Map.has_key?(item, "end_time")
      refute Map.has_key?(item, "parlview_url")
      refute Map.has_key?(item, "parlinfo_permalink")
      refute Map.has_key?(item, "date_tabled")
      refute Map.has_key?(item, "dataset")
    end

    test "paginates results", %{conn: conn} do
      for i <- 1..3 do
        insert_broadcast(%{"parlview_id" => "test-00#{i}", "title" => "Broadcast #{i}"})
      end

      conn = get(conn, ~p"/api/broadcasts?page=1&per_page=2")
      body = json_response(conn, 200)
      assert body["total"] == 3
      assert length(body["items"]) == 2
      assert body["page"] == 1
    end

    test "filters by date range using start_time", %{conn: conn} do
      insert_broadcast(%{
        "parlview_id" => "old-001",
        "title" => "Old Broadcast",
        "start_time" => "2025-06-01T09:00:00"
      })

      insert_broadcast(%{
        "parlview_id" => "new-001",
        "title" => "New Broadcast",
        "start_time" => "2026-04-01T09:00:00"
      })

      conn = get(conn, ~p"/api/broadcasts?from=2026-04-01&to=2026-04-30")
      body = json_response(conn, 200)
      titles = Enum.map(body["items"], & &1["title"])
      assert "New Broadcast" in titles
      refute "Old Broadcast" in titles
    end
  end

  describe "GET /api/broadcasts/latest" do
    test "returns empty list when no broadcasts exist", %{conn: conn} do
      conn = get(conn, ~p"/api/broadcasts/latest")
      body = json_response(conn, 200)
      assert body["items"] == []
    end

    test "returns broadcasts", %{conn: conn} do
      for i <- 1..3 do
        insert_broadcast(%{"parlview_id" => "lat-00#{i}", "title" => "Broadcast #{i}"})
      end

      conn = get(conn, ~p"/api/broadcasts/latest")
      body = json_response(conn, 200)
      assert length(body["items"]) == 3
    end

    test "respects limit param", %{conn: conn} do
      for i <- 1..5 do
        insert_broadcast(%{"parlview_id" => "lim-00#{i}", "title" => "Broadcast #{i}"})
      end

      conn = get(conn, ~p"/api/broadcasts/latest?limit=2")
      body = json_response(conn, 200)
      assert length(body["items"]) == 2
    end
  end

  describe "GET /api/broadcasts/:id" do
    test "returns broadcast by UUID", %{conn: conn} do
      broadcast = insert_broadcast()
      conn = get(conn, ~p"/api/broadcasts/#{broadcast.id}")
      body = json_response(conn, 200)
      assert body["item"]["id"] == broadcast.id
      assert body["item"]["title"] == "Senate Economics Committee Broadcast"
      assert Map.has_key?(body["item"], "source_url")
      refute Map.has_key?(body["item"], "dataset")
    end

    test "returns 404 for unknown UUID", %{conn: conn} do
      conn = get(conn, ~p"/api/broadcasts/00000000-0000-0000-0000-000000000000")
      body = json_response(conn, 404)
      assert body["error"] == "not found"
    end
  end
end
