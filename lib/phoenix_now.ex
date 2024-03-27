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

    if options[:open_browser] do
      Application.put_env(:phoenix, :browser_open, true)
    end

    path = module.__info__(:compile)[:source]
    basename = Path.basename(path)

    Application.put_env(:phoenix_live_reload, :dirs, [
      Path.dirname(path)
    ])

    options =
      [
        type: type,
        module: module,
        basename: basename
      ] ++ Keyword.take(options, [:port])

    children = [
      {Phoenix.PubSub, name: PhoenixNow.PubSub},
      PhoenixNow.Reloader,
      {PhoenixNow.Endpoint, options}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule PhoenixNow.DelegateController do
  @moduledoc false

  def init(options) do
    options
  end

  def call(conn, options) do
    %{type: :controller, module: controller} = conn.private.phoenix_now
    controller.call(conn, controller.init(options))
  end
end

defmodule PhoenixNow.DelegateLive do
  @moduledoc false
  use Phoenix.LiveView

  @impl true
  def mount(params, session, socket) do
    live().mount(params, session, socket)
  end

  @impl true
  def render(assigns) do
    live().render(assigns)
  end

  @impl true
  def handle_event(event, params, socket) do
    live().handle_event(event, params, socket)
  end

  @impl true
  def handle_info(message, socket) do
    live().handle_info(message, socket)
  end

  defp live do
    %{type: :live, module: live} = PhoenixNow.Endpoint.config(:phoenix_now)
    live
  end
end

defmodule PhoenixNow.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :phoenix_now

  defoverridable start_link: 1

  def start_link(options) do
    options =
      Keyword.validate!(
        options,
        [
          :type,
          :module,
          :port,
          :basename,
          :router
        ]
      )

    router =
      case options[:type] do
        :controller -> PhoenixNow.ControllerRouter
        :live -> PhoenixNow.LiveRouter
      end

    options = Keyword.put_new(options, :router, router)

    live_reload_options =
      if basename = options[:basename] do
        [
          live_reload: [
            debounce: 100,
            patterns: [
              ~r/#{basename}$/
            ],
            notify: [
              {"phoenix_now", [~r/#{basename}$/]}
            ]
          ]
        ]
      else
        []
      end

    Application.put_env(
      :phoenix_now,
      __MODULE__,
      [
        adapter: Bandit.PhoenixAdapter,
        http: [ip: {127, 0, 0, 1}, port: options[:port]],
        server: !!options[:port],
        live_view: [signing_salt: "aaaaaaaa"],
        secret_key_base: String.duplicate("a", 64),
        pubsub_server: PhoenixNow.PubSub,
        debug_errors: true,
        phoenix_now: Map.new(options)
      ] ++ live_reload_options
    )

    super([])
  end

  @session_options [
    store: :cookie,
    key: "_phoenix_now_key",
    signing_salt: "ll+Leuc3",
    same_site: "Lax",
    # 14 days
    max_age: 14 * 24 * 60 * 60
  ]

  socket "/live", Phoenix.LiveView.Socket
  socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket

  plug Phoenix.LiveReloader

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Session, @session_options

  plug :router

  defp router(conn, []) do
    config = conn.private.phoenix_endpoint.config(:phoenix_now)
    conn = Plug.Conn.put_private(conn, :phoenix_now, config)
    config.router.call(conn, [])
  end
end

defmodule PhoenixNow.ControllerRouter do
  @moduledoc false

  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :put_root_layout, html: {PhoenixNow.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through(:browser)

    get "/", PhoenixNow.DelegateController, :index
  end
end

defmodule PhoenixNow.LiveRouter do
  @moduledoc false

  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {PhoenixNow.Layouts, :root}
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default, layout: {PhoenixNow.Layouts, :live} do
      live "/", PhoenixNow.DelegateLive, :index
    end
  end
end

defmodule PhoenixNow.Test do
  defmacro __using__([{type, module}]) do
    module = Macro.expand(module, __ENV__)

    imports =
      if type == :live do
        quote do
          import(Phoenix.LiveViewTest)
        end
      end

    quote do
      import Phoenix.ConnTest
      module = unquote(module)
      type = unquote(type)
      unquote(imports)

      @endpoint PhoenixNow.Endpoint
      @phoenix_now [type: type, module: module]

      setup do
        {:ok, _} = @endpoint.start_link(@phoenix_now)
        :ok
      end
    end
  end
end

defmodule PhoenixNow.Reloader do
  @moduledoc false

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
  @moduledoc false

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
  @moduledoc false

  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end
