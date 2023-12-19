#!/usr/bin/env elixir
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
    <div style="padding: 1em;">
      <span style="font-family: monospace;">Count: <%= @count %></span>
      <button phx-click="inc">+</button>
      <button phx-click="dec">-</button>

      <p style="margin-top: 1em;">Now edit <code><%= __ENV__.file %></code> in your editor...</p>
    </div>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, count: socket.assigns.count + 1)}
  end

  def handle_event("dec", _params, socket) do
    {:noreply, assign(socket, count: socket.assigns.count - 1)}
  end
end

Logger.configure(level: :warning)
ExUnit.start()

defmodule HomeLiveTest do
  @view HomeLive
  use PhoenixNow.Case, async: true

  test "it works", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "Count: 0"
    assert render_click(view, :inc, %{}) =~ "Count: 1"
    assert render_click(view, :inc, %{}) =~ "Count: 2"
  end
end
