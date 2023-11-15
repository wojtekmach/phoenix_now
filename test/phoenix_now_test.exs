defmodule PhoenixNowTest do
  use ExUnit.Case
  doctest PhoenixNow

  test "greets the world" do
    assert PhoenixNow.hello() == :world
  end
end
