defmodule Pingdom.Mixfile do
  use Mix.Project

  def project do
    [app: :pingdom,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     aliases: aliases()]
  end

  def application do
    [extra_applications: [],
     applications: [:httpoison, :logger, :poison],
     mod: {Pingdom.Application, []}]
  end

  defp deps do
    [
      {:httpoison, "~> 0.11.0"},
      {:poison, "~> 3.0"},
      {:distillery, "~> 1.0"}
    ]
  end

  defp aliases, do: [vsn: &getvsn/1, project: &getproject/1]
  defp getproject([]), do: IO.puts("#{project()[:app]}")
  defp getvsn([]), do: IO.puts("#{project()[:app]}-#{project()[:version]}")
end
