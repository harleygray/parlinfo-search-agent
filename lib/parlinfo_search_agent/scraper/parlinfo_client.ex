defmodule ParlInfoSearchAgent.Scraper.ParlinfoClient do
  @behaviour ParlInfoSearchAgent.Scraper.ParlinfoClientBehaviour

  require Logger

  @base_url "http://localhost:4003"

  def scrape(url) do
    Logger.info("[parlinfo_client] POST /scrape — scraping: #{url}")

    case Req.post("#{@base_url}/scrape", json: %{url: url}, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        items = Map.get(body, "items", [])
        Logger.info("[parlinfo_client] 200 OK — #{length(items)} items returned")
        Logger.debug("[parlinfo_client] raw body: #{inspect(body)}")
        {:ok, items}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[parlinfo_client] #{status} error — body: #{inspect(body)}")
        {:error, "playwright_server returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("[parlinfo_client] request failed — #{inspect(reason)}")
        {:error, reason}
    end
  end

  def scrape_item(url, dataset) do
    Logger.info("[parlinfo_client] POST /scrape_item dataset=#{dataset} — #{url}")

    case Req.post("#{@base_url}/scrape_item",
           json: %{url: url, dataset: dataset},
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        fields = Map.get(body, "fields", %{})
        Logger.info("[parlinfo_client] scrape_item 200 OK — fields: #{inspect(Map.keys(fields))}")
        {:ok, fields}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[parlinfo_client] scrape_item #{status} error — body: #{inspect(body)}")
        {:error, "playwright_server returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("[parlinfo_client] scrape_item request failed — #{inspect(reason)}")
        {:error, reason}
    end
  end
end
