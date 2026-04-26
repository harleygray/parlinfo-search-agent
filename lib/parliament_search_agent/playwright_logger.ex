defmodule ParliamentSearchAgent.PlaywrightLogger do
  require Logger

  def log(data) do
    data
    |> String.trim()
    |> String.split("\n")
    |> Enum.each(&log_line/1)
  end

  # Lifecycle
  defp log_line("Playwright server listening on port " <> port),
    do: Logger.info("[playwright] ready — port #{String.trim(port)}")

  defp log_line("Chromium browser initialized"),
    do: Logger.info("[playwright] browser initialized")

  defp log_line("Shutting down playwright server..."),
    do: Logger.info("[playwright] shutting down")

  # Scrape flow
  defp log_line("scrape:start " <> rest),
    do: Logger.info("[playwright] scrape starting — #{rest}")

  defp log_line("scrape:navigated " <> rest),
    do: Logger.info("[playwright] page navigated — #{rest}")

  defp log_line("scrape:selector_wait"),
    do: Logger.debug("[playwright] waiting for selector")

  defp log_line("scrape:selector_found " <> rest),
    do: Logger.info("[playwright] selector matched — #{rest}")

  defp log_line("scrape:diag " <> rest),
    do: Logger.info("[playwright] diag — #{rest}")

  defp log_line("scrape:id_link" <> rest),
    do: Logger.info("[playwright] id_link#{rest}")

  defp log_line("scrape:selector_missing"),
    do: Logger.error("[playwright] selector not found — extraction will return empty")

  defp log_line("scrape:diag_saved " <> rest),
    do: Logger.info("[playwright] diagnostic saved — #{rest}")

  defp log_line("scrape:diag_write_error " <> reason),
    do: Logger.error("[playwright] diagnostic write failed — #{reason}")

  defp log_line("scrape:extracted " <> rest),
    do: Logger.info("[playwright] items extracted — #{rest}")

  defp log_line("scrape:done " <> rest),
    do: Logger.info("[playwright] scrape done — #{rest}")

  defp log_line("scrape:row_error " <> reason),
    do: Logger.warning("[playwright] row extraction error — #{reason}")

  # Errors
  defp log_line("Scrape error: " <> reason),
    do: Logger.error("[playwright] scrape error — #{reason}")

  defp log_line("Fatal startup error: " <> reason),
    do: Logger.error("[playwright] fatal startup error — #{reason}")

  # Fallback
  defp log_line(line) when byte_size(line) > 0,
    do: Logger.debug("[playwright] #{line}")

  defp log_line(_), do: :ok
end
