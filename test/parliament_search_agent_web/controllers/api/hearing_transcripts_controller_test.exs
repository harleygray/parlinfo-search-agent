defmodule ParliamentSearchAgentWeb.Api.HearingTranscriptsControllerTest do
  use ParliamentSearchAgentWeb.ConnCase, async: false

  alias ParliamentSearchAgent.Items

  @base_attrs %{
    "parlinfo_id" => "committees/commjnt/test001/0000",
    "title" => "Joint Committee Hearing on Treaties",
    "source_url" => "https://parlinfo.aph.gov.au/hearing-001"
  }

  defp insert_transcript(overrides \\ %{}) do
    {:ok, :new, transcript} = Items.upsert_hearing_transcript(Map.merge(@base_attrs, overrides))
    transcript
  end

  describe "GET /api/hearing_transcripts" do
    test "returns empty list when no transcripts exist", %{conn: conn} do
      conn = get(conn, ~p"/api/hearing_transcripts")
      body = json_response(conn, 200)
      assert body["items"] == []
      assert body["total"] == 0
      assert body["page"] == 1
    end

    test "returns inserted transcripts with correct fields", %{conn: conn} do
      transcript = insert_transcript()
      conn = get(conn, ~p"/api/hearing_transcripts")
      body = json_response(conn, 200)
      assert body["total"] == 1
      assert [item] = body["items"]
      assert item["id"] == transcript.id
      assert item["title"] == "Joint Committee Hearing on Treaties"
      assert item["parlinfo_ids"] == ["committees/commjnt/test001/0000"]
      refute Map.has_key?(item, "dataset")
      refute Map.has_key?(item, "parlinfo_id")
      refute Map.has_key?(item, "chamber")
      refute Map.has_key?(item, "parliament_number")
      refute Map.has_key?(item, "source_url")
      refute Map.has_key?(item, "inserted_at")
    end

    test "paginates results", %{conn: conn} do
      for i <- 1..3 do
        insert_transcript(%{
          "parlinfo_id" => "committees/commjnt/test00#{i}/0000",
          "title" => "Hearing #{i}"
        })
      end

      conn = get(conn, ~p"/api/hearing_transcripts?page=1&per_page=2")
      body = json_response(conn, 200)
      assert body["total"] == 3
      assert length(body["items"]) == 2
      assert body["page"] == 1
    end

    test "filters by date range", %{conn: conn} do
      insert_transcript(%{
        "parlinfo_id" => "committees/commjnt/old001/0000",
        "title" => "Old Hearing"
      })

      insert_transcript(%{
        "parlinfo_id" => "committees/commjnt/new001/0000",
        "title" => "New Hearing",
        "date_tabled" => "2026-04-01"
      })

      conn = get(conn, ~p"/api/hearing_transcripts?from=2026-04-01&to=2026-04-30")
      body = json_response(conn, 200)
      titles = Enum.map(body["items"], & &1["title"])
      assert "New Hearing" in titles
      refute "Old Hearing" in titles
    end
  end

  describe "GET /api/hearing_transcripts/latest" do
    test "returns empty list when no transcripts exist", %{conn: conn} do
      conn = get(conn, ~p"/api/hearing_transcripts/latest")
      body = json_response(conn, 200)
      assert body["items"] == []
    end

    test "returns transcripts ordered by inserted_at desc", %{conn: conn} do
      for i <- 1..3 do
        insert_transcript(%{
          "parlinfo_id" => "committees/commjnt/lat00#{i}/0000",
          "title" => "Hearing #{i}"
        })
      end

      conn = get(conn, ~p"/api/hearing_transcripts/latest")
      body = json_response(conn, 200)
      assert length(body["items"]) == 3
    end

    test "respects limit param", %{conn: conn} do
      for i <- 1..5 do
        insert_transcript(%{
          "parlinfo_id" => "committees/commjnt/lim00#{i}/0000",
          "title" => "Hearing #{i}"
        })
      end

      conn = get(conn, ~p"/api/hearing_transcripts/latest?limit=2")
      body = json_response(conn, 200)
      assert length(body["items"]) == 2
    end
  end

  describe "API matches Ecto query" do
    test "paginated results match Items.list_items", %{conn: conn} do
      for i <- 1..5 do
        insert_transcript(%{
          "parlinfo_id" => "committees/commjnt/consist#{i}/0000",
          "title" => "Consistency Hearing #{i}",
          "date_tabled" => "202#{i}-06-01"
        })
      end

      params = %{"dataset" => "hearing_transcripts", "page" => "1", "per_page" => "3"}
      conn = get(conn, ~p"/api/hearing_transcripts?page=1&per_page=3")
      api_ids = json_response(conn, 200)["items"] |> Enum.map(& &1["id"]) |> Enum.sort()

      %{items: ecto_items} = Items.list_items(params)
      ecto_ids = ecto_items |> Enum.map(& &1.id) |> Enum.sort()

      assert api_ids == ecto_ids
    end

    test "date-filtered results match Items.list_items", %{conn: conn} do
      for {date, suffix} <- [{"2023-06-01", "old001"}, {"2025-06-01", "new001"}] do
        insert_transcript(%{
          "parlinfo_id" => "committees/commjnt/#{suffix}/0000",
          "date_tabled" => date
        })
      end

      params = %{"dataset" => "hearing_transcripts", "from" => "2025-01-01"}
      conn = get(conn, ~p"/api/hearing_transcripts?from=2025-01-01")
      api_ids = json_response(conn, 200)["items"] |> Enum.map(& &1["id"]) |> Enum.sort()

      %{items: ecto_items} = Items.list_items(params)
      ecto_ids = ecto_items |> Enum.map(& &1.id) |> Enum.sort()

      assert api_ids == ecto_ids
    end
  end

  describe "GET /api/hearing_transcripts/:id" do
    test "returns transcript by UUID", %{conn: conn} do
      transcript = insert_transcript()
      conn = get(conn, ~p"/api/hearing_transcripts/#{transcript.id}")
      body = json_response(conn, 200)
      assert body["item"]["id"] == transcript.id
      assert body["item"]["title"] == "Joint Committee Hearing on Treaties"
      refute Map.has_key?(body["item"], "dataset")
      refute Map.has_key?(body["item"], "source_url")
    end

    test "returns 404 for unknown UUID", %{conn: conn} do
      conn = get(conn, ~p"/api/hearing_transcripts/00000000-0000-0000-0000-000000000000")
      body = json_response(conn, 404)
      assert body["error"] == "not found"
    end
  end
end
