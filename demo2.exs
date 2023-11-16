Mix.install([
  {:phoenix_now, github: "wojtekmach/phoenix_now"}
])

defmodule HomeController do
  use Phoenix.Controller, formats: [:html, :json]
  plug :put_layout, false

  def index(conn, params) do
    render(conn, :index, hello: params["hello"])
  end
end

defmodule HomeHTML do
  use Phoenix.Component

  def index(assigns) do
    ~H"""
    <%= if @hello do %>
      <p>Hello, <%= @hello %>!</p>
    <% else %>
      <a href="?hello=World">Say hello to the World</a>.
    <% end %>
    """
  end
end

{:ok, _} =
  PhoenixNow.start_link(
    routes: [
      {:get, "/", HomeController, :index}
    ]
  )

Process.sleep(:infinity)
