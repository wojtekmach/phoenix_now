defmodule PhoenixNow.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_now,
      version: "0.1.0",
      elixir: "~> 1.17-dev",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixNow.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.0"},
      {:phoenix_live_view, "~> 0.20"},
      {:bandit, "~> 1.0", override: true},

      # for some reason this needs to be runtime false
      {:phoenix_live_reload, "~> 1.0", runtime: false},
      {:file_system, "~> 1.0", override: true}
    ]
  end
end
