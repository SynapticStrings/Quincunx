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
      {:orchid,
       git: "https://github.com/SynapticStrings/Orchid.git", branch: "core", override: true},
      {:orchid_symbiont, git: "https://github.com/SynapticStrings/OrchidSymbiont.git"},
      {:lily, git: "https://github.com/SynapticStrings/Lily.git"}
    ]
  end
end
