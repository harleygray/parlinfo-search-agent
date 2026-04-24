defmodule ParlInfoSearchAgentWeb.DashboardLive do
  use ParlInfoSearchAgentWeb, :live_view

  import Ecto.Query
  alias ParlInfoSearchAgent.{Repo, Items}
  alias ParlInfoSearchAgent.Items.{Report, Broadcast, HearingTranscript}

  @refresh_interval 30_000
  @initial_feed_limit 50

  @workers [
    ParlInfoSearchAgent.Workers.ReportsScraper,
    ParlInfoSearchAgent.Workers.HearingTranscriptsScraper,
    ParlInfoSearchAgent.Workers.BroadcastsScraper
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ParlInfoSearchAgent.PubSub, "items:new")
      Phoenix.PubSub.subscribe(ParlInfoSearchAgent.PubSub, "items:updated")
      schedule_refresh()
    end

    {:ok,
     socket
     |> assign(:tab, "feed")
     |> assign(:feed_filter, "reports")
     |> assign(:reports_items, Items.get_latest(@initial_feed_limit, "reports"))
     |> assign(:transcripts_items, Items.get_latest(@initial_feed_limit, "hearing_transcripts"))
     |> assign(:broadcasts_items, Items.get_latest(@initial_feed_limit, "broadcasts"))
     |> assign(:job_stats, fetch_job_stats())
     |> assign(:dataset_stats, fetch_dataset_stats())}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket)
      when tab in ["api", "feed", "status"] do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:new_item, item}, socket) do
    case item_dataset(item) do
      "reports" ->
        updated = Enum.take([item | socket.assigns.reports_items], @initial_feed_limit)
        {:noreply, assign(socket, :reports_items, updated)}

      "hearing_transcripts" ->
        updated = Enum.take([item | socket.assigns.transcripts_items], @initial_feed_limit)
        {:noreply, assign(socket, :transcripts_items, updated)}

      "broadcasts" ->
        updated = Enum.take([item | socket.assigns.broadcasts_items], @initial_feed_limit)
        {:noreply, assign(socket, :broadcasts_items, updated)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:updated_item, %Report{} = item}, socket) do
    updated =
      Enum.map(socket.assigns.reports_items, fn r -> if r.id == item.id, do: item, else: r end)

    {:noreply, assign(socket, :reports_items, updated)}
  end

  def handle_info({:updated_item, %HearingTranscript{} = item}, socket) do
    updated =
      Enum.map(socket.assigns.transcripts_items, fn r -> if r.id == item.id, do: item, else: r end)

    {:noreply, assign(socket, :transcripts_items, updated)}
  end

  def handle_info({:updated_item, %Broadcast{} = item}, socket) do
    updated =
      Enum.map(socket.assigns.broadcasts_items, fn r -> if r.id == item.id, do: item, else: r end)

    {:noreply, assign(socket, :broadcasts_items, updated)}
  end

  def handle_info(:refresh, socket) do
    schedule_refresh()

    {:noreply,
     socket
     |> assign(:job_stats, fetch_job_stats())
     |> assign(:dataset_stats, fetch_dataset_stats())}
  end

  @impl true
  def handle_event("set_feed_filter", %{"dataset" => dataset}, socket) do
    {:noreply, assign(socket, :feed_filter, dataset)}
  end

  @impl true
  def handle_event("run_worker", %{"worker" => short_name}, socket) do
    require Logger
    Logger.info("[dashboard] run_worker clicked: #{short_name}")

    mod = Enum.find(@workers, fn m -> worker_short_name(m) == short_name end)

    socket =
      case mod && Oban.insert(mod.new(%{})) do
        {:ok, _job} ->
          Logger.info("[dashboard] job queued for #{short_name}")
          put_flash(socket, :info, "#{short_name} queued")

        {:error, reason} ->
          Logger.error("[dashboard] failed to queue #{short_name}: #{inspect(reason)}")
          put_flash(socket, :error, "Failed to queue #{short_name}: #{inspect(reason)}")

        nil ->
          Logger.error("[dashboard] unknown worker: #{short_name}")
          put_flash(socket, :error, "Unknown worker: #{short_name}")
      end

    {:noreply, assign(socket, :job_stats, fetch_job_stats())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="height: 100vh; overflow: hidden; display: flex; flex-direction: column;">
      <div
        class="flex items-center px-6"
        style="background-color: var(--color-primary); border-bottom: 2px solid var(--color-primary-dark); min-height: 3rem;"
      >
        <span class="text-lg font-semibold" style="color: white;">ParlInfo Search Agent</span>
        <details style="position: relative; display: flex; align-items: center; margin-left: 0.5rem;">
          <summary style="list-style: none; cursor: pointer; color: rgba(255,255,255,0.7); font-size: 0.7rem; display: inline-flex; align-items: center; justify-content: center; width: 1.1rem; height: 1.1rem; border: 1px solid rgba(255,255,255,0.4); border-radius: 50%;">
            ?
          </summary>
          <div style="position: absolute; top: calc(100% + 0.5rem); left: 0; width: 26rem; background: white; border-radius: 0.5rem; box-shadow: 0 4px 20px rgba(0,0,0,0.15); z-index: 50; padding: 1rem; color: #111827; font-size: 0.875rem; line-height: 1.6;">
            <p style="font-weight: 600; margin-bottom: 0.4rem; color: var(--color-primary);">
              ParlInfo Search Agent
            </p>
            <p>
              The goal of this project is to act as a <strong>data bridge</strong>
              between
              <a
                href="https://parlinfo.aph.gov.au/parlInfo/search/search.w3p;adv=yes"
                target="_blank"
                style="color: var(--color-primary); text-decoration: underline;"
              >
                ParlInfo
              </a>
              and consumers of parliamentary data. Though this data is technically public, it is nontrivial to access programatically.
            </p>
            <p style="margin-top: 0.5rem;">
              This MVP surfaces three API endpoints returning live, clean data for the following event types on ParlInfo:
            </p>
            <ul style="padding-left: 1.4rem; list-style: disc;">
              <li>Transcripts from Parliamentary Committee hearings</li>
              <li>Reports for all Committee Inquiries</li>
              <li>URLs for video/audio recordings for chambers in Parliament</li>
            </ul>

            <p style="margin-top: 0.5rem;">
              An immediate downstream consumer is <a
                href="https://civicforum.com.au/"
                target="_blank"
                style="color: var(--color-primary); text-decoration: underline;"
              >Civic Forum</a>, which needs a reliable feed of new parliamentary committee activity to power notifications and discussion threads. Other potential uses include data analysis tools and parliamentary tracking services.
            </p>
          </div>
        </details>
        <div class="flex gap-6" style="margin-left: auto;">
          <.link patch={~p"/?tab=feed"} style={tab_style(@tab, "feed")}>Live Feed</.link>
          <%!-- <.link patch={~p"/?tab=status"} style={tab_style(@tab, "status")}>Scrape Status</.link> --%>
          <.link patch={~p"/?tab=api"} style={tab_style(@tab, "api")}>API Reference</.link>
        </div>
      </div>

      <main
        class="px-6 max-w-5xl mx-auto"
        style="flex: 1; overflow: hidden; display: flex; flex-direction: column; width: 100%; padding-bottom: 1.5rem;"
      >
        <%= if @tab == "feed" do %>
          <.feed_tab
            reports={@reports_items}
            transcripts={@transcripts_items}
            broadcasts={@broadcasts_items}
            filter={@feed_filter}
          />
        <% end %>
        <%= if @tab == "status" do %>
          <div style="flex: 1; overflow-y: auto;">
            <.status_tab job_stats={@job_stats} dataset_stats={@dataset_stats} />
          </div>
        <% end %>
        <%= if @tab == "api" do %>
          <div style="flex: 1; overflow-y: auto;">
            <.api_tab />
          </div>
        <% end %>
      </main>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  defp feed_tab(assigns) do
    ~H"""
    <div style="padding-top: 1.25rem; flex: 1; overflow: hidden; display: flex; flex-direction: column;">
      <div style="display: flex; align-items: center; gap: 1rem; margin-bottom: 1.25rem; flex-shrink: 0;">
        <div style="display: flex; gap: 0.5rem; flex-shrink: 0;">
          <%= for {label, value} <- [{"Reports", "reports"}, {"Hearing Transcripts", "hearing_transcripts"}, {"Broadcasts", "broadcasts"}] do %>
            <button
              phx-click="set_feed_filter"
              phx-value-dataset={value}
              class={feed_filter_btn_class(@filter, value)}
            >
              {label}
            </button>
          <% end %>
        </div>
        <p style="font-size: 0.78rem; color: color-mix(in oklab, var(--color-base-content) 40%, transparent); margin: 0;">
          {feed_dataset_description(@filter)}
        </p>
      </div>

      <%= if @filter == "reports" do %>
        <%= if Enum.empty?(@reports) do %>
          <p style="color: #6b7280; padding: 1rem 0;">
            No reports yet. Scrape jobs will populate this feed.
          </p>
        <% else %>
          <div class="table-card" style="flex: 1; overflow-y: auto;">
            <table class="table" style="width: 100%; table-layout: fixed;">
              <colgroup>
                <col />
                <col style="width: 18rem;" />
                <col style="width: 7rem;" />
                <col style="width: 3rem;" />
                <col style="width: 7rem;" />
              </colgroup>
              <thead>
                <tr>
                  <th style="text-align: left;">Title</th>
                  <th style="text-align: left;">Committee</th>
                  <th style="text-align: left;">Date</th>
                  <th></th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for item <- @reports do %>
                  <tr>
                    <td style="text-align: left;">
                      <span style="font-weight: 500; overflow-wrap: break-word;">
                        {item.title}
                      </span>
                    </td>
                    <td style="text-align: left; font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 65%, transparent); overflow-wrap: break-word;">
                      {item.committee_name}
                    </td>
                    <td style="text-align: left; font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 60%, transparent); white-space: nowrap;">
                      {if item.date_tabled, do: Calendar.strftime(item.date_tabled, "%d %b %Y")}
                    </td>
                    <td style="text-align: center;">
                      <%= if item.pdf_url do %>
                        <a
                          href={item.pdf_url}
                          target="_blank"
                          rel="noopener"
                          title="View PDF"
                          style="color: var(--color-primary); display: inline-flex; align-items: center; justify-content: center; vertical-align: middle;"
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 256 256"
                            fill="currentColor"
                            style="width: 1rem; height: 1rem;"
                          >
                            <path d="M224,152a8,8,0,0,1-8,8H192v16h16a8,8,0,0,1,0,16H192v16a8,8,0,0,1-16,0V152a8,8,0,0,1,8-8h32A8,8,0,0,1,224,152ZM92,172a28,28,0,0,1-28,28H56v8a8,8,0,0,1-16,0V152a8,8,0,0,1,8-8H64A28,28,0,0,1,92,172Zm-16,0a12,12,0,0,0-12-12H56v24h8A12,12,0,0,0,76,172Zm88,8a36,36,0,0,1-36,36H112a8,8,0,0,1-8-8V152a8,8,0,0,1,8-8h16A36,36,0,0,1,164,180Zm-16,0a20,20,0,0,0-20-20h-8v40h8A20,20,0,0,0,148,180ZM40,112V40A16,16,0,0,1,56,24h96a8,8,0,0,1,5.66,2.34l56,56A8,8,0,0,1,216,88v24a8,8,0,0,1-16,0V96H152a8,8,0,0,1-8-8V40H56v72a8,8,0,0,1-16,0ZM160,80h28.69L160,51.31Z">
                            </path>
                          </svg>
                        </a>
                      <% end %>
                    </td>
                    <td style="text-align: right;">
                      <a
                        href={item.parlinfo_permalink || item.source_url}
                        target="_blank"
                        rel="noopener"
                        style="font-size: 0.75rem; color: var(--color-primary); text-decoration: underline; text-underline-offset: 2px; display: inline-flex; align-items: center; gap: 0.25rem;"
                      >
                        ParlInfo
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          viewBox="0 0 256 256"
                          fill="currentColor"
                          style="width: 0.75rem; height: 0.75rem; flex-shrink: 0;"
                        >
                          <path d="M229.66,109.66l-48,48a8,8,0,0,1-11.32-11.32L204.69,112H165a88,88,0,0,0-85.23,66,8,8,0,0,1-15.5-4A103.94,103.94,0,0,1,165,96h39.71L170.34,61.66a8,8,0,0,1,11.32-11.32l48,48A8,8,0,0,1,229.66,109.66ZM192,208H40V88a8,8,0,0,0-16,0V216a8,8,0,0,0,8,8H192a8,8,0,0,0,0-16Z">
                          </path>
                        </svg>
                      </a>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      <% end %>

      <%= if @filter == "hearing_transcripts" do %>
        <%= if Enum.empty?(@transcripts) do %>
          <p style="color: #6b7280; padding: 1rem 0;">
            No hearing transcripts yet. Scrape jobs will populate this feed.
          </p>
        <% else %>
          <div class="table-card" style="flex: 1; overflow-y: auto;">
            <table class="table" style="width: 100%; table-layout: fixed;">
              <colgroup>
                <col />
                <col style="width: 18rem;" />
                <col style="width: 7rem;" />
                <col style="width: 3rem;" />
                <col style="width: 7rem;" />
              </colgroup>
              <thead>
                <tr>
                  <th style="text-align: left;">Title</th>
                  <th style="text-align: left;">Committee</th>
                  <th style="text-align: left;">Date</th>
                  <th></th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for item <- @transcripts do %>
                  <tr>
                    <td style="text-align: left;">
                      <span style="font-weight: 500; overflow-wrap: break-word;">
                        {item.title}
                      </span>
                    </td>
                    <td style="text-align: left; font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 65%, transparent); overflow-wrap: break-word;">
                      {item.committee_name}
                    </td>
                    <td style="text-align: left; font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 60%, transparent); white-space: nowrap;">
                      {if item.date_tabled, do: Calendar.strftime(item.date_tabled, "%d %b %Y")}
                    </td>
                    <td style="text-align: center;">
                      <%= if item.pdf_url do %>
                        <a
                          href={item.pdf_url}
                          target="_blank"
                          rel="noopener"
                          title="View PDF"
                          style="color: var(--color-primary); display: inline-flex; align-items: center; justify-content: center; vertical-align: middle;"
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 256 256"
                            fill="currentColor"
                            style="width: 1rem; height: 1rem;"
                          >
                            <path d="M224,152a8,8,0,0,1-8,8H192v16h16a8,8,0,0,1,0,16H192v16a8,8,0,0,1-16,0V152a8,8,0,0,1,8-8h32A8,8,0,0,1,224,152ZM92,172a28,28,0,0,1-28,28H56v8a8,8,0,0,1-16,0V152a8,8,0,0,1,8-8H64A28,28,0,0,1,92,172Zm-16,0a12,12,0,0,0-12-12H56v24h8A12,12,0,0,0,76,172Zm88,8a36,36,0,0,1-36,36H112a8,8,0,0,1-8-8V152a8,8,0,0,1,8-8h16A36,36,0,0,1,164,180Zm-16,0a20,20,0,0,0-20-20h-8v40h8A20,20,0,0,0,148,180ZM40,112V40A16,16,0,0,1,56,24h96a8,8,0,0,1,5.66,2.34l56,56A8,8,0,0,1,216,88v24a8,8,0,0,1-16,0V96H152a8,8,0,0,1-8-8V40H56v72a8,8,0,0,1-16,0ZM160,80h28.69L160,51.31Z">
                            </path>
                          </svg>
                        </a>
                      <% end %>
                    </td>
                    <td style="text-align: right;">
                      <a
                        href={item.parlinfo_permalink || item.source_url}
                        target="_blank"
                        rel="noopener"
                        style="font-size: 0.75rem; color: var(--color-primary); text-decoration: underline; text-underline-offset: 2px; display: inline-flex; align-items: center; gap: 0.25rem;"
                      >
                        ParlInfo
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          viewBox="0 0 256 256"
                          fill="currentColor"
                          style="width: 0.75rem; height: 0.75rem; flex-shrink: 0;"
                        >
                          <path d="M229.66,109.66l-48,48a8,8,0,0,1-11.32-11.32L204.69,112H165a88,88,0,0,0-85.23,66,8,8,0,0,1-15.5-4A103.94,103.94,0,0,1,165,96h39.71L170.34,61.66a8,8,0,0,1,11.32-11.32l48,48A8,8,0,0,1,229.66,109.66ZM192,208H40V88a8,8,0,0,0-16,0V216a8,8,0,0,0,8,8H192a8,8,0,0,0,0-16Z">
                          </path>
                        </svg>
                      </a>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      <% end %>

      <%= if @filter == "broadcasts" do %>
        <%= if Enum.empty?(@broadcasts) do %>
          <p style="color: #6b7280; padding: 1rem 0;">
            No broadcasts yet. Scrape jobs will populate this feed.
          </p>
        <% else %>
          <div class="table-card" style="flex: 1; overflow-y: auto;">
            <table class="table" style="width: 100%; table-layout: fixed;">
              <colgroup>
                <col style="width: 22rem;" />
                <col style="width: 12rem;" />
                <col style="width: 10rem;" />
                <col style="width: 3.5rem;" />
              </colgroup>
              <thead>
                <tr>
                  <th style="text-align: left;">Title</th>
                  <th style="text-align: left;">Chamber</th>
                  <th style="text-align: left;">Start</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for item <- @broadcasts do %>
                  <tr>
                    <td style="text-align: left;">
                      <span style="font-weight: 500; overflow-wrap: break-word;">
                        {item.title}
                      </span>
                    </td>
                    <td style="text-align: left; font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 65%, transparent); overflow-wrap: break-word;">
                      {item.chamber}
                    </td>
                    <td style="text-align: left; font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 60%, transparent); white-space: nowrap;">
                      {if item.start_time, do: Calendar.strftime(item.start_time, "%d %b %Y %H:%M")}
                    </td>
                    <td style="text-align: center;">
                      <%= if item.source_url do %>
                        <a
                          href={item.source_url}
                          target="_blank"
                          rel="noopener"
                          title="Watch in ParlView"
                          style="color: var(--color-primary); display: inline-flex; align-items: center; justify-content: center; vertical-align: middle;"
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 256 256"
                            fill="currentColor"
                            style="width: 1rem; height: 1rem;"
                          >
                            <path d="M208,40H48A24,24,0,0,0,24,64V176a24,24,0,0,0,24,24H208a24,24,0,0,0,24-24V64A24,24,0,0,0,208,40Zm8,136a8,8,0,0,1-8,8H48a8,8,0,0,1-8-8V64a8,8,0,0,1,8-8H208a8,8,0,0,1,8,8Zm-48,48a8,8,0,0,1-8,8H96a8,8,0,0,1,0-16h64A8,8,0,0,1,168,224ZM157.66,106.34a8,8,0,0,1-11.32,11.32L136,107.31V152a8,8,0,0,1-16,0V107.31l-10.34,10.35a8,8,0,0,1-11.32-11.32l24-24a8,8,0,0,1,11.32,0Z">
                            </path>
                          </svg>
                        </a>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp status_tab(assigns) do
    ~H"""
    <div style="display: flex; flex-direction: column; gap: 1.5rem; padding-top: 1rem;">
      <div>
        <h2 style="font-size: 1.125rem; font-weight: 700; color: var(--color-primary); margin-bottom: 0.75rem;">
          Job Queue
        </h2>
        <div class="table-card">
          <table class="table">
            <thead>
              <tr>
                <th>Worker</th>
                <th>Pending</th>
                <th>Running</th>
                <th>Failed</th>
                <th>Last Run</th>
                <th>Next Run</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for stat <- @job_stats do %>
                <tr>
                  <td class="font-mono text-xs">
                    <div style="display: flex; align-items: center; gap: 0.5rem;">
                      <a
                        href={worker_info(stat.worker).url}
                        target="_blank"
                        rel="noopener"
                        style="color: var(--color-primary); text-decoration: underline; text-underline-offset: 2px;"
                      >
                        {stat.worker}
                      </a>
                      <details style="position: relative; display: inline-flex; align-items: center;">
                        <summary style="list-style: none; cursor: pointer; color: var(--color-primary); font-size: 0.75rem; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; font-family: var(--font-sans); flex-shrink: 0; user-select: none;">
                          i
                        </summary>
                        <div style="position: absolute; top: calc(100% + 0.4rem); left: 0; width: 18rem; background: white; border-radius: 0.5rem; box-shadow: 0 4px 20px rgba(0,0,0,0.12); z-index: 50; padding: 0.75rem 1rem; color: #374151; font-size: 0.8rem; line-height: 1.6; font-family: var(--font-sans); font-style: normal;">
                          {worker_info(stat.worker).description}
                        </div>
                      </details>
                    </div>
                  </td>
                  <td>{stat.available}</td>
                  <td>{stat.executing}</td>
                  <td class="text-error">{stat.retryable + stat.discarded}</td>
                  <td style="font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 60%, transparent);">
                    {format_last_run(stat.last_run)}
                  </td>
                  <td style="font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 60%, transparent);">
                    {format_next_run(stat.next_run)}
                  </td>
                  <td>
                    <button
                      phx-click="run_worker"
                      phx-value-worker={stat.worker}
                      style="font-size: 0.7rem; padding: 0.2rem 0.55rem; border-radius: 0.25rem; border: 1px solid var(--color-primary); color: var(--color-primary); background: transparent; cursor: pointer; white-space: nowrap;"
                    >
                      Run now
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <div>
        <h2 style="font-size: 1.125rem; font-weight: 700; color: var(--color-primary); margin-bottom: 0.75rem;">
          Last Successful Scrape
        </h2>
        <div class="table-card">
          <table class="table">
            <thead>
              <tr>
                <th>Dataset</th>
                <th>Item Count</th>
                <th>Last Seen</th>
              </tr>
            </thead>
            <tbody>
              <%= for stat <- @dataset_stats do %>
                <tr>
                  <td>{stat.dataset}</td>
                  <td>{stat.count}</td>
                  <td style="color: color-mix(in oklab, var(--color-base-content) 60%, transparent);">
                    {if stat.last_seen, do: stat.last_seen, else: "never"}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp api_tab(assigns) do
    ~H"""
    <div style="display: flex; flex-direction: column; gap: 2rem; padding-top: 1rem;">
      <%= for {dataset_label, endpoints} <- api_endpoint_groups() do %>
        <div>
          <h2 style="font-size: 1.125rem; font-weight: 700; color: var(--color-primary); margin-bottom: 0.75rem;">
            {dataset_label}
          </h2>
          <div style="display: flex; flex-direction: column; gap: 0.5rem;">
            <%= for endpoint <- endpoints do %>
              <details
                class="api-endpoint"
                style="border: 1px solid color-mix(in oklab, var(--color-base-content) 15%, transparent); border-radius: 0.5rem;"
              >
                <summary>
                  <svg
                    class="chevron"
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 256 256"
                    fill="currentColor"
                    style="width: 0.9rem; height: 0.9rem; color: color-mix(in oklab, var(--color-base-content) 40%, transparent); flex-shrink: 0;"
                  >
                    <path d="M213.66,101.66l-80,80a8,8,0,0,1-11.32,0l-80-80A8,8,0,0,1,53.66,90.34L128,164.69l74.34-74.35a8,8,0,0,1,11.32,11.32Z">
                    </path>
                  </svg>
                  <span style="background: #dcfce7; color: #166534; font-size: 0.7rem; font-weight: 700; padding: 0.15rem 0.45rem; border-radius: 0.25rem; flex-shrink: 0;">
                    GET
                  </span>
                  <code style="font-family: monospace; font-size: 0.875rem; color: var(--color-base-content);">
                    {endpoint.path}
                  </code>
                  <span style="font-size: 0.8rem; color: color-mix(in oklab, var(--color-base-content) 55%, transparent);">
                    {endpoint.description}
                  </span>
                </summary>
                <div style="padding: 1rem; display: flex; flex-direction: column; gap: 1rem;">
                  <%= if endpoint.params != [] do %>
                    <div>
                      <p style="font-size: 0.72rem; font-weight: 600; color: color-mix(in oklab, var(--color-base-content) 45%, transparent); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem;">
                        Parameters
                      </p>
                      <div style="border: 1px solid color-mix(in oklab, var(--color-base-content) 12%, transparent); border-radius: 0.375rem; overflow: hidden;">
                        <%= for {param, idx} <- Enum.with_index(endpoint.params) do %>
                          <div style={"padding: 0.6rem 0.85rem; #{if idx > 0, do: "border-top: 1px solid color-mix(in oklab, var(--color-base-content) 10%, transparent);", else: ""}"}>
                            <div style="display: flex; align-items: baseline; gap: 0.5rem; margin-bottom: 0.2rem;">
                              <span style="font-family: monospace; font-size: 0.8rem; font-weight: 600; color: var(--color-base-content);">
                                {param.name}
                              </span>
                              <span style="font-size: 0.72rem; color: color-mix(in oklab, var(--color-base-content) 45%, transparent);">
                                {param.type}
                              </span>
                              <%= if param.default do %>
                                <span style="font-size: 0.72rem; color: color-mix(in oklab, var(--color-base-content) 40%, transparent);">
                                  · default:
                                  <code style="font-family: monospace;">{param.default}</code>
                                </span>
                              <% end %>
                            </div>
                            <p style="font-size: 0.78rem; color: color-mix(in oklab, var(--color-base-content) 60%, transparent); margin: 0;">
                              {param.description}
                            </p>
                          </div>
                        <% end %>
                      </div>
                    </div>
                    <div>
                      <p style="font-size: 0.72rem; font-weight: 600; color: color-mix(in oklab, var(--color-base-content) 45%, transparent); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem;">
                        Example request
                      </p>
                      <pre style="background: color-mix(in oklab, var(--color-base-content) 5%, transparent); border-radius: 0.375rem; padding: 0.6rem 0.85rem; font-size: 0.78rem; overflow-x: auto; line-height: 1.5; margin: 0;">GET <%= endpoint.example_query %></pre>
                    </div>
                  <% end %>
                  <div>
                    <p style="font-size: 0.72rem; font-weight: 600; color: color-mix(in oklab, var(--color-base-content) 45%, transparent); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem;">
                      Example response
                    </p>
                    <pre style="background: color-mix(in oklab, var(--color-base-content) 5%, transparent); border-radius: 0.375rem; padding: 0.75rem; font-size: 0.72rem; overflow-x: auto; line-height: 1.5; margin: 0;"><%= endpoint.example %></pre>
                  </div>
                </div>
              </details>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp api_endpoint_groups do
    [
      {"Reports",
       [
         %{
           path: "/api/reports",
           description: "Paginated list of committee reports. Filter by date range.",
           params: [
             %{
               name: "from",
               type: "ISO date",
               default: nil,
               description: "Return items on or after this date (e.g. 2026-01-01)"
             },
             %{
               name: "to",
               type: "ISO date",
               default: nil,
               description: "Return items on or before this date"
             },
             %{name: "page", type: "integer", default: "1", description: "Page number"},
             %{
               name: "per_page",
               type: "integer",
               default: "20",
               description: "Items per page (max 100)"
             }
           ],
           example_query: "/api/reports?from=2026-01-01&to=2026-12-31&per_page=10",
           example: ~s({
  "items": [
    {
      "id": "018f4a2b-3c1d-7e8f-9a0b-1c2d3e4f5a6b",
      "parlinfo_ids": ["committees/reportsen/RB000778/0000", "committees/reportsen/RB000778/0001"],
      "title": "Inquiry into the National Disability Insurance Scheme",
      "date_tabled": "2026-03-15T00:00:00",
      "date_referred": "2025-08-01T00:00:00",
      "committee_name": "Senate Community Affairs Committee",
      "inquiry_name": "NDIS Independent Assessment Framework",
      "report_type": "Final",
      "pdf_url": "https://parlinfo.aph.gov.au/parlInfo/download/committees/reportsen/RB000778/toc_pdf/report.pdf",
      "parlinfo_permalink": "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id%3A%22committees%2Freportsen%2FRB000778%2F0000%22"
    }
  ],
  "total": 42,
  "page": 1,
  "per_page": 10
})
         },
         %{
           path: "/api/reports/latest",
           description: "Most recent reports by date tabled.",
           params: [
             %{
               name: "limit",
               type: "integer",
               default: "20",
               description: "Number of items to return (max 100)"
             }
           ],
           example_query: "/api/reports/latest?limit=5",
           example: ~s({
  "items": [
    {
      "id": "018f4a2b-3c1d-7e8f-9a0b-1c2d3e4f5a6b",
      "parlinfo_ids": ["committees/reportsen/RB000778/0000"],
      "title": "Inquiry into the National Disability Insurance Scheme",
      "date_tabled": "2026-03-15T00:00:00",
      "date_referred": "2025-08-01T00:00:00",
      "committee_name": "Senate Community Affairs Committee",
      "inquiry_name": "NDIS Independent Assessment Framework",
      "report_type": "Final",
      "pdf_url": "https://parlinfo.aph.gov.au/parlInfo/download/committees/reportsen/RB000778/toc_pdf/report.pdf",
      "parlinfo_permalink": "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id%3A%22committees%2Freportsen%2FRB000778%2F0000%22"
    }
  ]
})
         },
         %{
           path: "/api/reports/:id",
           description: "Fetch a single report by its UUID.",
           params: [],
           example: ~s({
  "item": {
    "id": "018f4a2b-3c1d-7e8f-9a0b-1c2d3e4f5a6b",
    "parlinfo_ids": ["committees/reportsen/RB000778/0000"],
    "title": "Inquiry into the National Disability Insurance Scheme",
    "date_tabled": "2026-03-15T00:00:00",
    "date_referred": "2025-08-01T00:00:00",
    "committee_name": "Senate Community Affairs Committee",
    "inquiry_name": "NDIS Independent Assessment Framework",
    "report_type": "Final",
    "pdf_url": "https://parlinfo.aph.gov.au/parlInfo/download/committees/reportsen/RB000778/toc_pdf/report.pdf",
    "parlinfo_permalink": "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id%3A%22committees%2Freportsen%2FRB000778%2F0000%22"
  }
})
         }
       ]},
      {"Hearing Transcripts",
       [
         %{
           path: "/api/hearing_transcripts",
           description: "Paginated list of committee hearing transcripts. Filter by date range.",
           params: [
             %{
               name: "from",
               type: "ISO date",
               default: nil,
               description: "Return items on or after this date"
             },
             %{
               name: "to",
               type: "ISO date",
               default: nil,
               description: "Return items on or before this date"
             },
             %{name: "page", type: "integer", default: "1", description: "Page number"},
             %{
               name: "per_page",
               type: "integer",
               default: "20",
               description: "Items per page (max 100)"
             }
           ],
           example_query: "/api/hearing_transcripts?from=2026-01-01&per_page=10",
           example: ~s({
  "items": [
    {
      "id": "019a1b2c-4d5e-6f7a-8b9c-0d1e2f3a4b5c",
      "parlinfo_ids": ["committees/estimate/E2026S01/0000", "committees/estimate/E2026S01/0001"],
      "title": "Supplementary Budget Estimates — Education and Employment",
      "date_tabled": "2026-02-10",
      "committee_name": "Senate Education and Employment Legislation Committee",
      "pdf_url": "https://parlinfo.aph.gov.au/parlInfo/download/committees/estimate/E2026S01/toc_pdf/transcript.pdf",
      "parlinfo_permalink": "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id%3A%22committees%2Festimate%2FE2026S01%2F0000%22"
    }
  ],
  "total": 14,
  "page": 1,
  "per_page": 10
})
         },
         %{
           path: "/api/hearing_transcripts/latest",
           description: "Most recent hearing transcripts by date tabled.",
           params: [
             %{
               name: "limit",
               type: "integer",
               default: "20",
               description: "Number of items to return (max 100)"
             }
           ],
           example_query: "/api/hearing_transcripts/latest?limit=5",
           example: ~s({
  "items": [
    {
      "id": "019a1b2c-4d5e-6f7a-8b9c-0d1e2f3a4b5c",
      "parlinfo_ids": ["committees/estimate/E2026S01/0000"],
      "title": "Supplementary Budget Estimates — Education and Employment",
      "date_tabled": "2026-02-10",
      "committee_name": "Senate Education and Employment Legislation Committee",
      "pdf_url": "https://parlinfo.aph.gov.au/parlInfo/download/committees/estimate/E2026S01/toc_pdf/transcript.pdf",
      "parlinfo_permalink": "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id%3A%22committees%2Festimate%2FE2026S01%2F0000%22"
    }
  ]
})
         },
         %{
           path: "/api/hearing_transcripts/:id",
           description: "Fetch a single hearing transcript by its UUID.",
           params: [],
           example: ~s({
  "item": {
    "id": "019a1b2c-4d5e-6f7a-8b9c-0d1e2f3a4b5c",
    "parlinfo_ids": ["committees/estimate/E2026S01/0000"],
    "title": "Supplementary Budget Estimates — Education and Employment",
    "date_tabled": "2026-02-10",
    "committee_name": "Senate Education and Employment Legislation Committee",
    "pdf_url": "https://parlinfo.aph.gov.au/parlInfo/download/committees/estimate/E2026S01/toc_pdf/transcript.pdf",
    "parlinfo_permalink": "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id%3A%22committees%2Festimate%2FE2026S01%2F0000%22"
  }
})
         }
       ]},
      {"Broadcasts",
       [
         %{
           path: "/api/broadcasts",
           description:
             "Paginated list of Parliament TV broadcast records. Filter by date range.",
           params: [
             %{
               name: "from",
               type: "ISO date",
               default: nil,
               description: "Return items on or after this date"
             },
             %{
               name: "to",
               type: "ISO date",
               default: nil,
               description: "Return items on or before this date"
             },
             %{name: "page", type: "integer", default: "1", description: "Page number"},
             %{
               name: "per_page",
               type: "integer",
               default: "20",
               description: "Items per page (max 100)"
             }
           ],
           example_query: "/api/broadcasts?from=2026-03-01&per_page=10",
           example: ~s({
  "items": [
    {
      "id": "01ab2c3d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
      "parlview_id": "4511416",
      "title": "Senate Environment and Communications Legislation Committee",
      "chamber": "Senate - Committee",
      "is_live": false,
      "source_url": "https://www.aph.gov.au/News_and_Events/Watch_Read_Listen/ParlView/video/4511416",
      "start_time": "2026-04-20T09:05:00",
      "duration": "08:40:00"
    }
  ],
  "total": 28,
  "page": 1,
  "per_page": 10
})
         },
         %{
           path: "/api/broadcasts/latest",
           description: "Most recently inserted broadcast records.",
           params: [
             %{
               name: "limit",
               type: "integer",
               default: "20",
               description: "Number of items to return (max 100)"
             }
           ],
           example_query: "/api/broadcasts/latest?limit=5",
           example: ~s({
  "items": [
    {
      "id": "01ab2c3d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
      "parlview_id": "4511416",
      "title": "Senate Environment and Communications Legislation Committee",
      "chamber": "Senate - Committee",
      "is_live": false,
      "source_url": "https://www.aph.gov.au/News_and_Events/Watch_Read_Listen/ParlView/video/4511416",
      "start_time": "2026-04-20T09:05:00",
      "duration": "08:40:00"
    }
  ]
})
         },
         %{
           path: "/api/broadcasts/:id",
           description: "Fetch a single broadcast record by its UUID.",
           params: [],
           example: ~s({
  "item": {
    "id": "01ab2c3d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
    "parlview_id": "123456",
    "title": "Senate Economics Legislation Committee — 20 March 2026",
    "chamber": "Senate",
    "is_live": false,
    "source_url": "https://www.aph.gov.au/News_and_Events/Watch_Read_Listen/ParlView/video/123456",
    "start_time": "2026-03-20T09:30:00",
    "duration": "3h 12m"
  }
})
         }
       ]}
    ]
  end

  defp fetch_job_stats do
    Enum.map(@workers, fn mod ->
      worker = inspect(mod)

      counts =
        from(j in Oban.Job,
          where: j.worker == ^worker,
          group_by: j.state,
          select: {j.state, count(j.id)}
        )
        |> Repo.all()
        |> Map.new()

      last_run =
        from(j in Oban.Job,
          where: j.worker == ^worker and j.state == "completed",
          order_by: [desc: j.completed_at],
          limit: 1,
          select: j.completed_at
        )
        |> Repo.one()

      next_run =
        from(j in Oban.Job,
          where: j.worker == ^worker and j.state == "scheduled",
          order_by: [asc: j.scheduled_at],
          limit: 1,
          select: j.scheduled_at
        )
        |> Repo.one()

      %{
        worker: worker_short_name(mod),
        available: Map.get(counts, "available", 0),
        executing: Map.get(counts, "executing", 0),
        retryable: Map.get(counts, "retryable", 0),
        discarded: Map.get(counts, "discarded", 0),
        last_run: last_run,
        next_run: next_run
      }
    end)
  end

  defp fetch_dataset_stats do
    [
      {"reports", Report},
      {"hearing_transcripts", HearingTranscript},
      {"broadcasts", Broadcast}
    ]
    |> Enum.map(fn {dataset, schema} ->
      {count, last_seen} =
        Repo.one(from i in schema, select: {count(i.id), max(i.inserted_at)})

      %{dataset: dataset, count: count || 0, last_seen: last_seen}
    end)
  end

  defp item_dataset(%Report{}), do: "reports"
  defp item_dataset(%Broadcast{}), do: "broadcasts"
  defp item_dataset(%HearingTranscript{}), do: "hearing_transcripts"

  defp feed_dataset_description("reports"),
    do: "Committee reports from joint, Senate, and House committees"

  defp feed_dataset_description("hearing_transcripts"),
    do: "Estimates hearings and committee proceedings"

  defp feed_dataset_description("broadcasts"),
    do: "Parliament TV broadcast records"

  defp feed_dataset_description(_), do: ""

  defp feed_filter_btn_class(current, value) do
    if current == value, do: "feed-filter-btn feed-filter-btn--active", else: "feed-filter-btn"
  end

  defp worker_short_name(mod), do: mod |> inspect() |> String.split(".") |> List.last()

  defp format_last_run(nil), do: "never"

  defp format_last_run(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)
    "#{duration_ago(diff)} at #{Calendar.strftime(dt, "%H:%M")}"
  end

  defp format_next_run(nil), do: "—"

  defp format_next_run(%DateTime{} = dt) do
    diff = DateTime.diff(dt, DateTime.utc_now(), :second)
    "#{duration_until(diff)} at #{Calendar.strftime(dt, "%H:%M")}"
  end

  defp duration_ago(s) when s < 60, do: "just now"
  defp duration_ago(s) when s < 3600, do: "#{div(s, 60)}m ago"
  defp duration_ago(s) when s < 86400, do: "#{div(s, 3600)}h ago"
  defp duration_ago(s), do: "#{div(s, 86400)}d ago"

  defp duration_until(s) when s <= 0, do: "now"
  defp duration_until(s) when s < 60, do: "in #{s}s"
  defp duration_until(s) when s < 3600, do: "in #{div(s, 60)}m"
  defp duration_until(s) when s < 86400, do: "in #{div(s, 3600)}h"
  defp duration_until(s), do: "in #{div(s, 86400)}d"

  defp tab_style(current, tab) do
    if current == tab do
      "color: white; font-weight: 700; text-decoration: underline;"
    else
      "color: rgba(255,255,255,0.7);"
    end
  end

  defp worker_info("ReportsScraper"),
    do: %{
      url:
        "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p;adv=yes;orderBy=customrank;page=0;query=Dataset%3Areportjnt,reportsen,reportrep;resCount=100",
      description:
        "Searches ParlInfo for parliamentary committee reports from joint, Senate, and House of Representatives committees (datasets: reportjnt, reportsen, reportrep)."
    }

  defp worker_info("HearingTranscriptsScraper"),
    do: %{
      url:
        "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p;adv=yes;orderBy=customrank;page=0;query=Dataset%3Aestimate,comSen,comJoint,comRep;resCount=100",
      description:
        "Searches ParlInfo for committee hearing transcripts and Hansard across estimates, Senate, joint, and House committees (datasets: estimate, comSen, comJoint, comRep)."
    }

  defp worker_info("BroadcastsScraper"),
    do: %{
      url:
        "https://parlinfo.aph.gov.au/parlInfo/search/summary/summary.w3p;adv=yes;orderBy=customrank;page=0;query=Dataset%3AbroadcastComm,broadcastCommReps,broadcastCommJnt,broadcastCommSen;resCount=100",
      description:
        "Searches ParlInfo for broadcast and video recordings of committee proceedings across all chamber types (datasets: broadcastComm, broadcastCommReps, broadcastCommJnt, broadcastCommSen)."
    }

  defp worker_info(_), do: %{url: "#", description: ""}

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
