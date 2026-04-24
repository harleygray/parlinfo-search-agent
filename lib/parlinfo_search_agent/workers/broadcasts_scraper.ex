defmodule ParlInfoSearchAgent.Workers.BroadcastsScraper do
  use Oban.Worker, queue: :scraper, max_attempts: 3

  require Logger

  alias ParlInfoSearchAgent.Items
  alias ParlInfoSearchAgent.Items.Broadcast

  @dataset "broadcasts"

  @parlview_client Application.compile_env(
                     :parlinfo_search_agent,
                     :parlview_client,
                     ParlInfoSearchAgent.Scraper.ParlViewClient
                   )

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("[#{@dataset}] Starting scrape via ParlView API")

    with {:ok, videos} <- @parlview_client.fetch_recent(100) do
      Logger.info("[#{@dataset}] ParlView returned #{length(videos)} events")

      {new_count, existing_count} =
        Enum.reduce(videos, {0, 0}, fn video, {new, existing} ->
          attrs = map_video(video)

          case Items.upsert_broadcast(attrs) do
            {:ok, :new, broadcast} ->
              scrape_broadcast_detail(broadcast)
              {new + 1, existing}

            {:ok, :existing} ->
              # Re-check broadcasts that were previously live — they may have ended
              scrape_if_still_live(attrs["parlview_id"])
              {new, existing + 1}

            {:error, reason} ->
              Logger.error(
                "[#{@dataset}] Failed to upsert #{video["titleId"]}: #{inspect(reason)}"
              )

              {new, existing + 1}
          end
        end)

      Logger.info("[#{@dataset}] Done — #{new_count} new, #{existing_count} already existed")
      :ok
    else
      {:error, reason} ->
        Logger.error("[#{@dataset}] Scrape failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # For existing broadcasts that are still marked live, fetch detail to check if they've ended
  defp scrape_if_still_live(parlview_id) do
    case Items.get_broadcast_by_parlview_id(parlview_id) do
      %Broadcast{is_live: true} = broadcast -> scrape_broadcast_detail(broadcast)
      _ -> :ok
    end
  end

  defp scrape_broadcast_detail(broadcast) do
    case @parlview_client.fetch_event(broadcast.parlview_id) do
      {:ok, detail} ->
        update_attrs = map_detail(detail, broadcast.start_time)

        case Items.update_broadcast(broadcast, update_attrs) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[#{@dataset}] Failed to update detail for #{broadcast.parlview_id}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.warning(
          "[#{@dataset}] Detail fetch failed for #{broadcast.parlview_id}: #{inspect(reason)}"
        )
    end
  end

  defp map_video(video) do
    title_id = video["titleId"]
    recording_from = parse_parlview_datetime(video["recordingFrom"])

    %{
      "parlview_id" => title_id,
      "title" => video["parlViewTitle"],
      "chamber" => derive_chamber(video),
      "start_time" => recording_from,
      "source_url" =>
        "https://www.aph.gov.au/News_and_Events/Watch_Read_Listen/ParlView/video/#{title_id}"
    }
  end

  defp map_detail(detail, start_time) do
    is_live = detail["isLive"] == true
    recording_to = detail["recordingTo"]
    # Duration is only computable once the event has ended and recordingTo is set
    duration = if !is_live, do: compute_duration(start_time, recording_to), else: nil
    %{"is_live" => is_live, "duration" => duration}
  end

  # Strip timezone offset: "2026-02-05T10:50:00+11:00" → "2026-02-05T10:50:00"
  defp parse_parlview_datetime(nil), do: nil
  defp parse_parlview_datetime(dt_string), do: String.slice(dt_string, 0, 19)

  defp derive_chamber(video) do
    title = String.downcase(video["parlViewTitle"] || "")

    cond do
      String.contains?(title, "joint") -> "Joint Committee"
      String.contains?(title, "house") -> "House of Representatives - Committee"
      String.contains?(title, "senate") -> "Senate - Committee"
      true -> video["eventSubGroup"] || video["eventGroup"]
    end
  end

  defp compute_duration(nil, _), do: nil
  defp compute_duration(_, nil), do: nil

  defp compute_duration(%NaiveDateTime{} = start_time, recording_to_str) do
    end_str = parse_parlview_datetime(recording_to_str)

    with end_str when not is_nil(end_str) <- end_str,
         {:ok, end_time} <- NaiveDateTime.from_iso8601(end_str) do
      diff = NaiveDateTime.diff(end_time, start_time)
      h = div(diff, 3600)
      m = div(rem(diff, 3600), 60)
      s = rem(diff, 60)
      :io_lib.format(~c"~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
    else
      _ -> nil
    end
  end
end
