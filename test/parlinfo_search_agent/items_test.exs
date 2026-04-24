defmodule ParlInfoSearchAgent.ItemsTest do
  use ParlInfoSearchAgent.DataCase, async: true

  alias ParlInfoSearchAgent.Items
  alias ParlInfoSearchAgent.Items.{Report, Broadcast}

  # Section-style ID mirrors real ParlInfo data; doc-level ID is everything before /0000
  @section_id "committees/reportsen/test001/0000"
  @doc_id "committees/reportsen/test001"

  @report_attrs %{
    "parlinfo_id" => @section_id,
    "title" => "Inquiry into something important",
    "source_url" => "https://parlinfo.aph.gov.au/test-001"
  }

  describe "upsert_report/1" do
    test "inserts a new report, stores doc-level parlinfo_id, and returns {:ok, :new, report}" do
      assert {:ok, :new, report} = Items.upsert_report(@report_attrs)
      assert report.parlinfo_id == @doc_id
      assert report.parlinfo_ids == [@section_id]
      assert report.title == "Inquiry into something important"
    end

    test "returns {:ok, :existing} on duplicate section_id" do
      assert {:ok, :new, _} = Items.upsert_report(@report_attrs)
      assert {:ok, :existing} = Items.upsert_report(@report_attrs)
      assert length(Items.get_latest(10, "reports")) == 1
    end

    test "collapses multiple sections of the same document into one row" do
      section0 = Map.put(@report_attrs, "parlinfo_id", "committees/reportsen/test001/0000")
      section1 = Map.put(@report_attrs, "parlinfo_id", "committees/reportsen/test001/0001")
      section2 = Map.put(@report_attrs, "parlinfo_id", "committees/reportsen/test001/0002")

      assert {:ok, :new, _} = Items.upsert_report(section0)
      assert {:ok, :existing} = Items.upsert_report(section1)
      assert {:ok, :existing} = Items.upsert_report(section2)

      [report] = Items.get_latest(10, "reports")
      assert report.parlinfo_id == "committees/reportsen/test001"
      assert length(report.parlinfo_ids) == 3
      assert "committees/reportsen/test001/0001" in report.parlinfo_ids
      assert "committees/reportsen/test001/0002" in report.parlinfo_ids
    end

    test "returns {:error, changeset} for missing required fields" do
      assert {:error, changeset} = Items.upsert_report(%{"parlinfo_id" => "a/b/c/0000"})
      assert %{title: ["can't be blank"], source_url: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns {:error, changeset} when parlinfo_id is nil" do
      attrs = Map.put(@report_attrs, "parlinfo_id", nil)
      assert {:error, changeset} = Items.upsert_report(attrs)
      assert %{parlinfo_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "broadcasts :new_item on new insert" do
      Phoenix.PubSub.subscribe(ParlInfoSearchAgent.PubSub, "items:new")

      assert {:ok, :new, _} = Items.upsert_report(@report_attrs)

      assert_receive {:new_item, %Report{parlinfo_id: @doc_id}}
    end

    test "does not broadcast on existing item or additional sections" do
      Phoenix.PubSub.subscribe(ParlInfoSearchAgent.PubSub, "items:new")

      Items.upsert_report(@report_attrs)
      Items.upsert_report(@report_attrs)

      assert_receive {:new_item, _}
      refute_receive {:new_item, _}
    end

    test "accepts optional fields" do
      attrs =
        Map.merge(@report_attrs, %{
          "committee_name" => "Senate Economics Committee",
          "date_tabled" => "2025-03-15",
          "pdf_url" => "https://parlinfo.aph.gov.au/test-001.pdf"
        })

      assert {:ok, :new, report} = Items.upsert_report(attrs)
      assert report.committee_name == "Senate Economics Committee"
      assert report.date_tabled == ~N[2025-03-15 00:00:00]
    end
  end

  describe "get_latest/2" do
    test "returns items for a given dataset" do
      for i <- 1..3 do
        Items.upsert_report(%{
          "parlinfo_id" => "committees/reportsen/item#{i}/0000",
          "title" => "Item #{i}",
          "source_url" => "https://example.com/#{i}"
        })
      end

      items = Items.get_latest(10, "reports")
      assert length(items) == 3
      assert Enum.all?(items, &is_struct(&1, Report))
    end

    test "respects the limit" do
      for i <- 1..5 do
        Items.upsert_report(%{
          "parlinfo_id" => "committees/reportsen/item#{i}/0000",
          "title" => "Item #{i}",
          "source_url" => "https://example.com/#{i}"
        })
      end

      assert length(Items.get_latest(3, "reports")) == 3
    end
  end

  describe "list_items/1" do
    test "filters by dataset" do
      Items.upsert_report(@report_attrs)

      Items.upsert_broadcast(%{
        "parlview_id" => "bcast-001",
        "title" => "Some Broadcast",
        "source_url" => "https://example.com/bcast"
      })

      result = Items.list_items(%{"dataset" => "reports"})
      assert result.total == 1
      assert hd(result.items) |> is_struct(Report)

      bcast_result = Items.list_items(%{"dataset" => "broadcasts"})
      assert bcast_result.total == 1
      assert hd(bcast_result.items) |> is_struct(Broadcast)
    end

    test "paginates results" do
      for i <- 1..25 do
        Items.upsert_report(%{
          "parlinfo_id" => "committees/reportsen/item#{i}/0000",
          "title" => "Item #{i}",
          "source_url" => "https://example.com/#{i}"
        })
      end

      page1 = Items.list_items(%{"dataset" => "reports", "page" => "1", "per_page" => "10"})
      assert page1.total == 25
      assert length(page1.items) == 10
      assert page1.page == 1

      page3 = Items.list_items(%{"dataset" => "reports", "page" => "3", "per_page" => "10"})
      assert length(page3.items) == 5
    end
  end
end
