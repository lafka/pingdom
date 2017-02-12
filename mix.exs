defmodule Pingdom.Mixfile do
  use Mix.Project

  def project do
    [app: :pingdom,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger],
     applications: [:httpoison],
     mod: {Pingdom.Application, []}]
  end

  defp deps do
    [
      {:httpoison, "~> 0.11.0"}
    ]
  end
end
