defmodule PhoenixNow do
  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  def start_link(options) do
    options =
      Keyword.validate!(options, [
        :live,
        :controller,
        port: 4000,
        open_browser: true
      ])

    {type, module} =
      cond do
        live = options[:live] ->
          {:live, live}

        controller = options[:controller] ->
          {:controller, controller}

        true ->
          raise "missing :live or :controller"
      end

    router = Module.concat(module, Router)
    endpoint = Module.concat(module, Endpoint)
    Process.put(:phoenix_now, %{type: type, module: module, router: router, endpoint: endpoint})
    path = module.__info__(:compile)[:source]
    basename = Path.basename(path)

    Application.put_env(:phoenix_live_reload, :dirs, [
      Path.dirname(path)
    ])

    if options[:open_browser] do
      Application.put_env(:phoenix, :browser_open, true)
    end

    Application.put_env(:phoenix_now, endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: options[:port]],
      server: true,
      live_view: [signing_salt: "aaaaaaaa"],
      secret_key_base: String.duplicate("a", 64),
      pubsub_server: PhoenixNow.PubSub,
      debug_errors: true,
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

    defmodule router do
      config = Process.get(:phoenix_now)

      use Phoenix.Router
      import Phoenix.LiveView.Router

      pipeline :browser do
        plug :accepts, ["html"]
        plug :put_root_layout, html: {PhoenixNow.Layouts, :root}
        # TODO
        # plug :protect_from_forgery
        plug :put_secure_browser_headers
      end

      scope "/" do
        pipe_through(:browser)

        case config.type do
          :live ->
            live_session :default, layout: {PhoenixNow.Layouts, :live} do
              live "/", module, :index
            end

          :controller ->
            get "/", module, :index
        end
      end
    end

    defmodule endpoint do
      router = Process.get(:phoenix_now).router

      use Phoenix.Endpoint, otp_app: :phoenix_now

      socket "/live", Phoenix.LiveView.Socket
      socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket

      plug Phoenix.LiveReloader

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()

      plug router
    end

    children = [
      {Phoenix.PubSub, name: PhoenixNow.PubSub},
      PhoenixNow.Reloader,
      endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule PhoenixNow.Reloader do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl true
  def init(_) do
    :ok = Phoenix.PubSub.subscribe(PhoenixNow.PubSub, "phoenix_now")
    {:ok, nil}
  end

  @impl true
  def handle_info({:phoenix_live_reload, "phoenix_now", path}, state) do
    recompile(path)
    {:noreply, state}
  end

  defp recompile(path) do
    {:ok, quoted} =
      path
      |> File.read!()
      |> Code.string_to_quoted()

    Macro.prewalk(quoted, fn
      {:defmodule, _, [mod, _]} = ast ->
        mod =
          case mod do
            {:__aliases__, _, parts} -> Module.concat(parts)
            mod when is_atom(mod) -> mod
          end

        :code.purge(mod)
        :code.delete(mod)
        Code.eval_quoted(ast, [], file: path)
        :ok

      ast ->
        ast
    end)
  end
end

defmodule PhoenixNow.Layouts do
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
