defmodule ParliamentSearchAgent.Scraper.PlaywrightServer do
  use GenServer
  require Logger

  @port 4003
  @health_url "http://localhost:#{@port}/health"
  @startup_timeout 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ready? do
    case Req.get(@health_url, receive_timeout: 2_000, retry: false) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    if port_in_use?() do
      Logger.info("playwright_server already running on port #{@port}, reusing it")
      {:ok, %{port: nil}}
    else
      port = open_port()
      wait_for_ready()
      {:ok, %{port: port}}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    ParliamentSearchAgent.PlaywrightLogger.log(data)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("playwright_server exited with status #{status}")
    {:stop, :port_crashed, state}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.error("playwright_server port exited: #{inspect(reason)}")
    {:stop, :port_crashed, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: nil}), do: :ok

  def terminate(_reason, %{port: port}) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> System.cmd("kill", ["-TERM", "#{os_pid}"])
      _ -> :ok
    end

    if Port.info(port) != nil, do: Port.close(port)
  end

  defp open_port do
    node = System.find_executable("node") || raise "node not found in PATH"

    Port.open(
      {:spawn_executable, node},
      [:binary, :exit_status, {:cd, File.cwd!()}, {:args, ["playwright_server/server.js"]}]
    )
  end

  defp port_in_use? do
    case :gen_tcp.connect(~c"localhost", @port, [], 1_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  defp wait_for_ready(elapsed \\ 0) do
    cond do
      elapsed >= @startup_timeout ->
        raise "playwright_server did not become ready within #{@startup_timeout}ms"

      ready?() ->
        :ok

      true ->
        Process.sleep(500)
        wait_for_ready(elapsed + 500)
    end
  end
end
