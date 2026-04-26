defmodule ParliamentSearchAgent.Scraper.ParlViewClientBehaviour do
  @callback fetch_recent(limit :: pos_integer()) :: {:ok, [map()]} | {:error, term()}
  @callback fetch_event(parlview_id :: String.t()) :: {:ok, map()} | {:error, term()}
end
