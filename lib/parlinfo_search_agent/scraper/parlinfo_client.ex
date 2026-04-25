defmodule ParlInfoSearchAgent.Scraper.ParlinfoClient do
  @behaviour ParlInfoSearchAgent.Scraper.ParlinfoClientBehaviour

  require Logger

  @base_url "http://localhost:4003"

  def scrape(url) do
    case Req.post("#{@base_url}/scrape", json: %{url: url}, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        items = Map.get(body, "items", [])
        Logger.debug("[parlinfo_client] raw body: #{inspect(body)}")
        {:ok, items}

      {:ok, %{status: 403, body: %{"error" => "waf_blocked"}}} ->
        Logger.warning("[parlinfo_client] WAF block detected on #{url}")
        {:error, :waf_blocked}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[parlinfo_client] #{status} error — body: #{inspect(body)}")
        {:error, "playwright_server returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("[parlinfo_client] request failed — #{inspect(reason)}")
        {:error, reason}
    end
  end

  def scrape_item(url, dataset) do
    case Req.post("#{@base_url}/scrape_item",
           json: %{url: url, dataset: dataset},
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        fields = Map.get(body, "fields", %{})
        Logger.debug("[parlinfo_client] scrape_item fields: #{inspect(Map.keys(fields))}")
        {:ok, fields}

      {:ok, %{status: 403, body: %{"error" => "waf_blocked"}}} ->
        Logger.warning("[parlinfo_client] WAF block on scrape_item #{url}")
        {:error, :waf_blocked}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[parlinfo_client] scrape_item #{status} error — body: #{inspect(body)}")
        {:error, "playwright_server returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("[parlinfo_client] scrape_item request failed — #{inspect(reason)}")
        {:error, reason}
    end
  end
end
