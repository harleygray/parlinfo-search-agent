[
  project: "parliament-search-agent",
  cwd: "/home/harley/Projects/parliament-search-agent",
  tasks: [
    %{
      id: :phoenix_server,
      label: "Phoenix Server",
      description: "ParlInfo search Phoenix app at localhost:4002",
      command: "mix",
      args: ["phx.server"],
      type: :long_running,
      restart: :manual,
      port: 4002,
      env: %{}
    },
    %{
      id: :playwright_server,
      label: "Playwright Server",
      description: "Headless browser scraper for ParlInfo at localhost:4003",
      command: "node",
      args: ["playwright_server/server.js"],
      type: :long_running,
      restart: :manual,
      port: 4003,
      env: %{}
    }
  ]
]
