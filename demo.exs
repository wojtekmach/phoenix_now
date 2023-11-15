Mix.install([
  {:phoenix_now, github: "wojtekmach/phoenix_now"}
])

defmodule Demo.HomeView do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def render(assigns) do
    ~H"""
    <%= @count %>
    <button phx-click="inc">+</button>
    <button phx-click="dec">-</button>

    <p>Now edit the file...</p>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event("dec", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count - 1)}
  end
end

defmodule Main do
  def main do
    {:ok, _} = PhoenixNow.start(view: Demo.HomeView)
    Process.sleep(:infinity)
  end
end

Main.main()
