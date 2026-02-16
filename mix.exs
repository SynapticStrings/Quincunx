defmodule Quincunx.MixProject do
  use Mix.Project

  def project do
    [
      app: :quincunx,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Quincunx.Application, []}
    ]
  end

  defp deps do
    [
      {:orchid, "~> 0.5"}
    ]
  end
end
