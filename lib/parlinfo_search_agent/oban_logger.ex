defmodule ParlInfoSearchAgent.ObanLogger do
  require Logger

  def attach do
    :telemetry.attach_many(
      "parlinfo-oban-logger",
      [
        [:oban, :job, :start],
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &ParlInfoSearchAgent.ObanLogger.handle_event/4,
      nil
    )
  end

  def handle_event([:oban, :job, :start], _measurements, meta, _config) do
    job = meta.job

    Logger.info(
      "[oban] ▶ starting — worker: #{short(job.worker)}, id: #{job.id}, attempt: #{job.attempt}/#{job.max_attempts}"
    )
  end

  def handle_event([:oban, :job, :stop], measurements, meta, _config) do
    job = meta.job
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    case meta.state do
      :success ->
        Logger.info("[oban] ✓ completed — worker: #{short(job.worker)}, id: #{job.id}, #{ms}ms")

      :failure ->
        Logger.warning(
          "[oban] ✗ failed (will retry) — worker: #{short(job.worker)}, id: #{job.id}, result: #{inspect(meta.result)}, #{ms}ms"
        )

      :cancelled ->
        Logger.warning("[oban] cancelled — worker: #{short(job.worker)}, id: #{job.id}")

      :discard ->
        Logger.error(
          "[oban] discarded (exhausted retries) — worker: #{short(job.worker)}, id: #{job.id}, result: #{inspect(meta.result)}"
        )

      other ->
        Logger.info("[oban] #{other} — worker: #{short(job.worker)}, id: #{job.id}, #{ms}ms")
    end
  end

  def handle_event([:oban, :job, :exception], measurements, meta, _config) do
    job = meta.job
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "[oban] exception — worker: #{short(job.worker)}, id: #{job.id}, #{meta.kind}: #{inspect(meta.reason)}, #{ms}ms"
    )
  end

  defp short(worker), do: worker |> String.split(".") |> List.last()
end
