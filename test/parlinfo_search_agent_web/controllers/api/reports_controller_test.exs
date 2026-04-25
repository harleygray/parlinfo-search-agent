defmodule ParlInfoSearchAgentWeb.Api.ReportsControllerTest do
  use ParlInfoSearchAgentWeb.ConnCase, async: false

  alias ParlInfoSearchAgent.Items

  @base_attrs %{
    "parlinfo_id" => "committees/reportsen/test001/0000",
    "title" => "Inquiry into Something Important",
    "source_url" => "https://parlinfo.aph.gov.au/test-001"
  }

  defp insert_report(overrides \\ %{}) do
    {:ok, :new, report} = Items.upsert_report(Map.merge(@base_attrs, overrides))
    report
  end

  describe "GET /api/reports" do
    test "returns empty list when no reports exist", %{conn: conn} do
      conn = get(conn, ~p"/api/reports")
      body = json_response(conn, 200)
      assert body["items"] == []
      assert body["total"] == 0
      assert body["page"] == 1
    end

    test "returns inserted reports with correct fields", %{conn: conn} do
      report = insert_report()
      conn = get(conn, ~p"/api/reports")
      body = json_response(conn, 200)
      assert body["total"] == 1
      assert [item] = body["items"]
      assert item["id"] == report.id
      assert item["title"] == "Inquiry into Something Important"
      assert item["parlinfo_ids"] == ["committees/reportsen/test001/0000"]
      refute Map.has_key?(item, "dataset")
      refute Map.has_key?(item, "parlinfo_id")
      refute Map.has_key?(item, "source_url")
      refute Map.has_key?(item, "chamber")
      refute Map.has_key?(item, "inserted_at")
    end

    test "paginates results", %{conn: conn} do
      for i <- 1..3 do
        insert_report(%{
          "parlinfo_id" => "committees/reportsen/test00#{i}/0000",
          "title" => "Report #{i}"
        })
      end

      conn = get(conn, ~p"/api/reports?page=1&per_page=2")
      body = json_response(conn, 200)
      assert body["total"] == 3
      assert body["per_page"] == 2
      assert length(body["items"]) == 2
      assert body["page"] == 1
    end

    test "filters by date range", %{conn: conn} do
      insert_report(%{
        "parlinfo_id" => "committees/reportsen/old001/0000",
        "title" => "Old Report"
      })

      insert_report(%{
        "parlinfo_id" => "committees/reportsen/new001/0000",
        "title" => "New Report",
        "date_tabled" => "2026-04-01"
      })

      conn = get(conn, ~p"/api/reports?from=2026-04-01&to=2026-04-30")
      body = json_response(conn, 200)
      titles = Enum.map(body["items"], & &1["title"])
      assert "New Report" in titles
      refute "Old Report" in titles
    end
  end

  describe "GET /api/reports/latest" do
    test "returns empty list when no reports exist", %{conn: conn} do
      conn = get(conn, ~p"/api/reports/latest")
      body = json_response(conn, 200)
      assert body["items"] == []
    end

    test "returns reports ordered by inserted_at desc", %{conn: conn} do
      for i <- 1..3 do
        insert_report(%{
          "parlinfo_id" => "committees/reportsen/lat00#{i}/0000",
          "title" => "Report #{i}"
        })
      end

      conn = get(conn, ~p"/api/reports/latest")
      body = json_response(conn, 200)
      assert length(body["items"]) == 3
    end

    test "respects limit param", %{conn: conn} do
      for i <- 1..5 do
        insert_report(%{
          "parlinfo_id" => "committees/reportsen/lim00#{i}/0000",
          "title" => "Report #{i}"
        })
      end

      conn = get(conn, ~p"/api/reports/latest?limit=2")
      body = json_response(conn, 200)
      assert length(body["items"]) == 2
    end
  end

  describe "API matches Ecto query" do
    test "paginated results match Items.list_items", %{conn: conn} do
      for i <- 1..5 do
        insert_report(%{
          "parlinfo_id" => "committees/reportsen/consist#{i}/0000",
          "title" => "Consistency Report #{i}",
          "date_tabled" => "202#{i}-06-01"
        })
      end

      params = %{"dataset" => "reports", "page" => "1", "per_page" => "3"}
      conn = get(conn, ~p"/api/reports?page=1&per_page=3")
      api_ids = json_response(conn, 200)["items"] |> Enum.map(& &1["id"]) |> Enum.sort()

      %{items: ecto_items} = Items.list_items(params)
      ecto_ids = ecto_items |> Enum.map(& &1.id) |> Enum.sort()

      assert api_ids == ecto_ids
    end

    test "date-filtered results match Items.list_items", %{conn: conn} do
      for {date, suffix} <- [{"2023-06-01", "old001"}, {"2025-06-01", "new001"}] do
        insert_report(%{
          "parlinfo_id" => "committees/reportsen/#{suffix}/0000",
          "date_tabled" => date
        })
      end

      params = %{"dataset" => "reports", "from" => "2025-01-01"}
      conn = get(conn, ~p"/api/reports?from=2025-01-01")
      api_ids = json_response(conn, 200)["items"] |> Enum.map(& &1["id"]) |> Enum.sort()

      %{items: ecto_items} = Items.list_items(params)
      ecto_ids = ecto_items |> Enum.map(& &1.id) |> Enum.sort()

      assert api_ids == ecto_ids
    end
  end

  describe "GET /api/reports/:id" do
    test "returns report by UUID", %{conn: conn} do
      report = insert_report()
      conn = get(conn, ~p"/api/reports/#{report.id}")
      body = json_response(conn, 200)
      assert body["item"]["id"] == report.id
      assert body["item"]["title"] == "Inquiry into Something Important"
      refute Map.has_key?(body["item"], "dataset")
      refute Map.has_key?(body["item"], "source_url")
    end

    test "returns 404 for unknown UUID", %{conn: conn} do
      conn = get(conn, ~p"/api/reports/00000000-0000-0000-0000-000000000000")
      body = json_response(conn, 404)
      assert body["error"] == "not found"
    end
  end
end
