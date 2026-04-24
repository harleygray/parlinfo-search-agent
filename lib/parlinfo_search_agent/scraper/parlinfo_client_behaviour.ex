defmodule ParlInfoSearchAgent.Scraper.ParlinfoClientBehaviour do
  @callback scrape(url :: String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback scrape_item(url :: String.t(), dataset :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
