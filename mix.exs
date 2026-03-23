defmodule Quincunx.MixProject do
  use Mix.Project

  def project do
    [
      app: :quincunx,
      version: "0.3.2",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Quincunx.Application, []}
    ]
  end

  defp deps do
    [
      {:orchid, "~> 0.5"},
      {:orchid_symbiont, "~> 0.1"},
      {:orchid_stratum, "~> 0.1"}
    ]
  end
end
