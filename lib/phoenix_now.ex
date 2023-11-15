defmodule PhoenixNow.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: PhoenixNow.PubSub},
      {PhoenixNow.Reloader, Demo.HomeView}
    ]

    opts = [strategy: :one_for_one, name: PhoenixNow.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule PhoenixNow do
  def start(view: view) do
    Demo.HomeView = view

    path = view.__info__(:compile)[:source]
    basename = Path.basename(path)

    Application.put_env(:phoenix_live_reload, :dirs, [
      Path.dirname(path)
    ])

    Application.put_env(:phoenix_now, PhoenixNow.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: 4000],
      server: true,
      live_view: [signing_salt: "aaaaaaaa"],
      secret_key_base: String.duplicate("a", 64),
      pubsub_server: PhoenixNow.PubSub,
      live_reload: [
        debounce: 100,
        patterns: [
          ~r/#{basename}$/
        ],
        notify: [
          {"phoenix_now", [~r/#{basename}$/]}
        ]
      ]
    )

    Application.put_env(:phoenix, :browser_open, true)

    Supervisor.start_child(PhoenixNow.Supervisor, PhoenixNow.Endpoint)
  end
end

defmodule PhoenixNow.Reloader do
  use GenServer

  def start_link(module) do
    GenServer.start_link(__MODULE__, module)
  end

  @impl true
  def init(module) do
    :ok = Phoenix.PubSub.subscribe(PhoenixNow.PubSub, "phoenix_now")
    {:ok, %{module: module}}
  end

  @impl true
  def handle_info({:phoenix_live_reload, "phoenix_now", path}, state) do
    recompile(state.module, path)
    {:noreply, state}
  end

  defp recompile(module, path) do
    {:ok, quoted} =
      path
      |> File.read!()
      |> Code.string_to_quoted()

    {:__block__, _,
     [
       {{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, _} | rest
     ]} = quoted

    Macro.prewalk(rest, fn
      {:defmodule, _, [{:__aliases__, _, parts} | _]} = ast ->
        if Module.concat(parts) == module do
          Code.eval_quoted(ast, [], file: path)
          :ok
        else
          ast
        end

      ast ->
        ast
    end)
  end
end

defmodule PhoenixNow.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:put_root_layout, html: {PhoenixNow.LayoutView, :root})
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default, layout: {PhoenixNow.LayoutView, :live} do
      live("/", Demo.HomeView, :index, as: :home)
    end
  end
end

defmodule PhoenixNow.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_now
  socket("/live", Phoenix.LiveView.Socket)
  socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
  plug(Phoenix.LiveReloader)
  plug(PhoenixNow.Router)
end

defmodule PhoenixNow.LayoutView do
  use Phoenix.Component

  def render("root.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def render("live.html", assigns) do
    ~H"""
    <script src={"https://cdn.jsdelivr.net/npm/phoenix@#{phx_vsn()}/priv/static/phoenix.min.js"}>
    </script>
    <script
      src={"https://cdn.jsdelivr.net/npm/phoenix_live_view@#{lv_vsn()}/priv/static/phoenix_live_view.min.js"}
    >
    </script>
    <script>
      let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket)
      liveSocket.connect()
    </script>
    <%= @inner_content %>
    """
  end

  defp phx_vsn, do: Application.spec(:phoenix, :vsn)
  defp lv_vsn, do: Application.spec(:phoenix_live_view, :vsn)
end

defmodule PhoenixNow.ErrorView do
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end
