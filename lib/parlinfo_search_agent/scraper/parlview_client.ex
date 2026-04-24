defmodule ParlInfoSearchAgent.Scraper.ParlViewClient do
  @behaviour ParlInfoSearchAgent.Scraper.ParlViewClientBehaviour

  require Logger

  @vodapi_base "https://vodapi.aph.gov.au/api"

  @impl true
  def fetch_recent(limit \\ 20) do
    params = URI.encode_query(%{"searchString" => "", "pageSize" => limit, "page" => 0})
    url = "#{@vodapi_base}/search?#{params}"
    Logger.info("[parlview_client] GET #{url}")

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"searchResults" => %{"videos" => videos}}}}
      when is_list(videos) ->
        Logger.info("[parlview_client] fetch_recent — #{length(videos)} events returned")
        {:ok, videos}

      {:ok, %{status: 200, body: %{"searchResults" => %{"totalItems" => 0}}}} ->
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "[parlview_client] fetch_recent #{status} — #{inspect(body) |> String.slice(0..200)}"
        )

        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("[parlview_client] fetch_recent error — #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def fetch_event(parlview_id) do
    url = "#{@vodapi_base}/search/parlview/#{parlview_id}"
    Logger.info("[parlview_client] GET #{url}")

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"videoDetails" => details}}} when is_map(details) ->
        {:ok, details}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "[parlview_client] fetch_event #{status} for #{parlview_id} — #{inspect(body) |> String.slice(0..200)}"
        )

        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error(
          "[parlview_client] fetch_event error for #{parlview_id} — #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
