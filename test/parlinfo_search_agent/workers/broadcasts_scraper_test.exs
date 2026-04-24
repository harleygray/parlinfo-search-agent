defmodule ParlInfoSearchAgent.Workers.BroadcastsScraperTest do
  use ParlInfoSearchAgent.DataCase, async: false
  use Oban.Testing, repo: ParlInfoSearchAgent.Repo

  import Mox

  alias ParlInfoSearchAgent.Workers.BroadcastsScraper
  alias ParlInfoSearchAgent.Items
  alias ParlInfoSearchAgent.Items.Broadcast
  alias ParlInfoSearchAgent.Scraper.MockParlViewClient

  setup :verify_on_exit!

  @valid_video %{
    "titleId" => "9001",
    "parlViewTitle" => "Senate Economics Committee",
    "eventGroup" => "Committees",
    "eventSubGroup" => "",
    "recordingFrom" => "2026-04-01T09:00:00+11:00"
  }

  @live_detail %{
    "titleId" => "9001",
    "isLive" => true,
    "recordingFrom" => "2026-04-01T09:00:00+11:00",
    "recordingTo" => nil
  }

  @ended_detail %{
    "titleId" => "9001",
    "isLive" => false,
    "recordingFrom" => "2026-04-01T09:00:00+11:00",
    "recordingTo" => "2026-04-01T12:30:00+11:00"
  }

  test "perform/1 upserts scraped items and returns :ok" do
    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, [@valid_video]} end)
    expect(MockParlViewClient, :fetch_event, fn _id -> {:ok, @ended_detail} end)

    assert :ok = perform_job(BroadcastsScraper, %{})

    assert [item] = Items.get_latest(10, "broadcasts")
    assert is_struct(item, Broadcast)
    assert item.parlview_id == "9001"
    assert item.title == "Senate Economics Committee"
    assert item.chamber == "Senate - Committee"
    assert item.is_live == false
  end

  test "perform/1 sets is_live true and leaves duration nil for live events" do
    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, [@valid_video]} end)
    expect(MockParlViewClient, :fetch_event, fn _id -> {:ok, @live_detail} end)

    assert :ok = perform_job(BroadcastsScraper, %{})

    [item] = Items.get_latest(10, "broadcasts")
    assert item.is_live == true
    assert item.duration == nil
  end

  test "perform/1 populates duration when event has ended" do
    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, [@valid_video]} end)
    expect(MockParlViewClient, :fetch_event, fn _id -> {:ok, @ended_detail} end)

    assert :ok = perform_job(BroadcastsScraper, %{})

    [item] = Items.get_latest(10, "broadcasts")
    assert item.is_live == false
    assert item.duration == "03:30:00"
  end

  test "perform/1 re-fetches detail for existing live broadcasts" do
    # First run: inserts as live
    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, [@valid_video]} end)
    expect(MockParlViewClient, :fetch_event, fn _id -> {:ok, @live_detail} end)
    assert :ok = perform_job(BroadcastsScraper, %{})

    [item] = Items.get_latest(10, "broadcasts")
    assert item.is_live == true
    assert item.duration == nil

    # Second run: same video returned, broadcast is still live so detail is re-fetched;
    # this time it has ended
    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, [@valid_video]} end)
    expect(MockParlViewClient, :fetch_event, fn _id -> {:ok, @ended_detail} end)
    assert :ok = perform_job(BroadcastsScraper, %{})

    [updated] = Items.get_latest(10, "broadcasts")
    assert updated.is_live == false
    assert updated.duration == "03:30:00"
  end

  test "perform/1 does not re-fetch detail for already-ended broadcasts" do
    expect(MockParlViewClient, :fetch_recent, 2, fn _limit -> {:ok, [@valid_video]} end)
    # fetch_event called once (on insert), not again on second run since is_live: false
    expect(MockParlViewClient, :fetch_event, fn _id -> {:ok, @ended_detail} end)

    assert :ok = perform_job(BroadcastsScraper, %{})
    assert :ok = perform_job(BroadcastsScraper, %{})

    assert length(Items.get_latest(10, "broadcasts")) == 1
  end

  test "perform/1 fetches detail for each new item" do
    videos = [
      %{
        "titleId" => "9001",
        "parlViewTitle" => "Broadcast A",
        "eventGroup" => "Committees",
        "eventSubGroup" => "",
        "recordingFrom" => "2026-04-01T09:00:00+11:00"
      },
      %{
        "titleId" => "9002",
        "parlViewTitle" => "Broadcast B",
        "eventGroup" => "Committees",
        "eventSubGroup" => "",
        "recordingFrom" => "2026-04-02T09:00:00+11:00"
      }
    ]

    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, videos} end)
    expect(MockParlViewClient, :fetch_event, 2, fn _id -> {:ok, @ended_detail} end)

    assert :ok = perform_job(BroadcastsScraper, %{})
    assert length(Items.get_latest(10, "broadcasts")) == 2
  end

  test "perform/1 returns :ok with empty results" do
    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, []} end)

    assert :ok = perform_job(BroadcastsScraper, %{})
    assert [] = Items.get_latest(10, "broadcasts")
  end

  test "perform/1 returns error tuple on fetch failure" do
    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:error, :econnrefused} end)

    assert {:error, :econnrefused} = perform_job(BroadcastsScraper, %{})
  end

  test "perform/1 broadcasts PubSub event for new items" do
    Phoenix.PubSub.subscribe(ParlInfoSearchAgent.PubSub, "items:new")

    expect(MockParlViewClient, :fetch_recent, fn _limit -> {:ok, [@valid_video]} end)
    expect(MockParlViewClient, :fetch_event, fn _id -> {:ok, @ended_detail} end)

    assert :ok = perform_job(BroadcastsScraper, %{})
    assert_receive {:new_item, %Broadcast{parlview_id: "9001"}}
  end
end
