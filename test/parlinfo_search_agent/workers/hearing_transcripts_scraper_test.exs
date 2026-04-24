defmodule ParlInfoSearchAgent.Workers.HearingTranscriptsScraperTest do
  use ParlInfoSearchAgent.DataCase, async: false
  use Oban.Testing, repo: ParlInfoSearchAgent.Repo

  import Mox

  alias ParlInfoSearchAgent.Workers.HearingTranscriptsScraper
  alias ParlInfoSearchAgent.Items
  alias ParlInfoSearchAgent.Items.HearingTranscript
  alias ParlInfoSearchAgent.Scraper.MockParlinfoClient

  setup :verify_on_exit!

  @valid_item %{
    "parlinfo_id" => "committees/commjnt/com001/0000",
    "title" => "Joint Standing Committee on Treaties — Hearing",
    "source_url" => "https://parlinfo.aph.gov.au/com-001"
  }

  test "perform/1 upserts scraped items and returns :ok" do
    expect(MockParlinfoClient, :scrape, fn _url -> {:ok, [@valid_item]} end)
    expect(MockParlinfoClient, :scrape_item, fn _url, _dataset -> {:ok, %{}} end)

    assert :ok = perform_job(HearingTranscriptsScraper, %{})

    assert [item] = Items.get_latest(10, "hearing_transcripts")
    assert is_struct(item, HearingTranscript)
    assert item.parlinfo_id == "committees/commjnt/com001"
    assert item.parlinfo_ids == ["committees/commjnt/com001/0000"]
  end

  test "perform/1 scrapes detail page for each new document" do
    items = [
      %{
        "parlinfo_id" => "committees/commjnt/com001/0000",
        "title" => "Hearing A",
        "source_url" => "https://example.com/1"
      },
      %{
        "parlinfo_id" => "committees/commjnt/com002/0000",
        "title" => "Hearing B",
        "source_url" => "https://example.com/2"
      }
    ]

    expect(MockParlinfoClient, :scrape, fn _url -> {:ok, items} end)
    expect(MockParlinfoClient, :scrape_item, 2, fn _url, _dataset -> {:ok, %{}} end)

    assert :ok = perform_job(HearingTranscriptsScraper, %{})

    inserted = Items.get_latest(10, "hearing_transcripts")
    assert length(inserted) == 2
    assert Enum.all?(inserted, &is_struct(&1, HearingTranscript))
  end

  test "perform/1 returns :ok with empty scrape results" do
    expect(MockParlinfoClient, :scrape, fn _url -> {:ok, []} end)

    assert :ok = perform_job(HearingTranscriptsScraper, %{})
    assert [] = Items.get_latest(10, "hearing_transcripts")
  end

  test "perform/1 returns error tuple on scrape failure" do
    expect(MockParlinfoClient, :scrape, fn _url -> {:error, :timeout} end)

    assert {:error, :timeout} = perform_job(HearingTranscriptsScraper, %{})
  end

  test "perform/1 does not insert duplicate items on repeated runs" do
    expect(MockParlinfoClient, :scrape, 2, fn _url -> {:ok, [@valid_item]} end)
    # scrape_item only fires for the first insert, not the duplicate
    expect(MockParlinfoClient, :scrape_item, fn _url, _dataset -> {:ok, %{}} end)

    assert :ok = perform_job(HearingTranscriptsScraper, %{})
    assert :ok = perform_job(HearingTranscriptsScraper, %{})

    assert length(Items.get_latest(10, "hearing_transcripts")) == 1
  end
end
