defmodule ParlInfoSearchAgent.Workers.ReportsScraperTest do
  use ParlInfoSearchAgent.DataCase, async: false
  use Oban.Testing, repo: ParlInfoSearchAgent.Repo

  import Mox

  alias ParlInfoSearchAgent.Workers.ReportsScraper
  alias ParlInfoSearchAgent.Items
  alias ParlInfoSearchAgent.Items.Report
  alias ParlInfoSearchAgent.Scraper.MockParlinfoClient

  setup :verify_on_exit!

  @valid_item %{
    "parlinfo_id" => "committees/reportsen/rpt001/0000",
    "title" => "Inquiry into Defence Housing",
    "source_url" => "https://parlinfo.aph.gov.au/rpt-001"
  }

  test "perform/1 upserts scraped items and returns :ok" do
    expect(MockParlinfoClient, :scrape, fn _url -> {:ok, [@valid_item]} end)
    expect(MockParlinfoClient, :scrape_item, fn _url, _dataset -> {:ok, %{}} end)

    assert :ok = perform_job(ReportsScraper, %{})

    assert [item] = Items.get_latest(10, "reports")
    assert is_struct(item, Report)
    assert item.parlinfo_id == "committees/reportsen/rpt001"
    assert item.parlinfo_ids == ["committees/reportsen/rpt001/0000"]
    assert item.title == "Inquiry into Defence Housing"
  end

  test "perform/1 scrapes detail page for each new document" do
    items = [
      %{
        "parlinfo_id" => "committees/reportsen/rpt001/0000",
        "title" => "Report A",
        "source_url" => "https://example.com/1"
      },
      %{
        "parlinfo_id" => "committees/reportsen/rpt002/0000",
        "title" => "Report B",
        "source_url" => "https://example.com/2"
      }
    ]

    expect(MockParlinfoClient, :scrape, fn _url -> {:ok, items} end)
    expect(MockParlinfoClient, :scrape_item, 2, fn _url, _dataset -> {:ok, %{}} end)

    assert :ok = perform_job(ReportsScraper, %{})

    inserted = Items.get_latest(10, "reports")
    assert length(inserted) == 2
    assert Enum.all?(inserted, &is_struct(&1, Report))
  end

  test "perform/1 only scrapes detail once when multiple sections of the same document appear" do
    items = [
      %{
        "parlinfo_id" => "committees/reportsen/rpt001/0000",
        "title" => "Report A",
        "source_url" => "https://example.com/1"
      },
      %{
        "parlinfo_id" => "committees/reportsen/rpt001/0001",
        "title" => "Report A : Chapter 1 :",
        "source_url" => "https://example.com/2"
      },
      %{
        "parlinfo_id" => "committees/reportsen/rpt001/0002",
        "title" => "Report A : Chapter 2 :",
        "source_url" => "https://example.com/3"
      }
    ]

    expect(MockParlinfoClient, :scrape, fn _url -> {:ok, items} end)
    # scrape_item fired once for the document, not once per section
    expect(MockParlinfoClient, :scrape_item, 1, fn _url, _dataset -> {:ok, %{}} end)

    assert :ok = perform_job(ReportsScraper, %{})

    [report] = Items.get_latest(10, "reports")
    assert report.parlinfo_id == "committees/reportsen/rpt001"
    assert length(report.parlinfo_ids) == 3
  end

  test "perform/1 returns :ok with empty scrape results" do
    expect(MockParlinfoClient, :scrape, fn _url -> {:ok, []} end)

    assert :ok = perform_job(ReportsScraper, %{})
    assert [] = Items.get_latest(10, "reports")
  end

  test "perform/1 returns error tuple on scrape failure" do
    expect(MockParlinfoClient, :scrape, fn _url -> {:error, :timeout} end)

    assert {:error, :timeout} = perform_job(ReportsScraper, %{})
  end

  test "perform/1 returns error tuple on connection error" do
    expect(MockParlinfoClient, :scrape, fn _url ->
      {:error, "playwright_server returned 500: \"Internal Server Error\""}
    end)

    assert {:error, _} = perform_job(ReportsScraper, %{})
  end

  test "perform/1 does not insert duplicate items on repeated runs" do
    expect(MockParlinfoClient, :scrape, 2, fn _url -> {:ok, [@valid_item]} end)
    # scrape_item only fires for the first insert, not the duplicate
    expect(MockParlinfoClient, :scrape_item, fn _url, _dataset -> {:ok, %{}} end)

    assert :ok = perform_job(ReportsScraper, %{})
    assert :ok = perform_job(ReportsScraper, %{})

    assert length(Items.get_latest(10, "reports")) == 1
  end
end
