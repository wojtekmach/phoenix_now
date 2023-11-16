Mix.install([
  {:phoenix_now, github: "wojtekmach/phoenix_now"}
])

defmodule HomeLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def render(assigns) do
    ~H"""
    <%= @count %>
    <button phx-click="inc">+</button>
    <button phx-click="dec">-</button>

    <p>Now edit <code><%= __ENV__.file %></code> in your editor...</p>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event("dec", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count - 1)}
  end
end

{:ok, _} = PhoenixNow.start_link(live: HomeLive)
Process.sleep(:infinity)
