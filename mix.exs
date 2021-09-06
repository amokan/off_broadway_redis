defmodule OffBroadwayRedis.MixProject do
  use Mix.Project

  @version "1.0.0"
  @description "An opinionated Redis list connector for Broadway"
  @repo_url "https://github.com/amokan/off_broadway_redis"

  def project do
    [
      app: :off_broadway_redis,
      version: @version,
      elixir: "~> 1.7",
      name: "OffBroadwayRedis",
      description: @description,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:broadway, "~> 1.0"},
      {:ex_doc, ">= 0.25.0", only: [:dev, :docs], runtime: false},
      {:excoveralls, "~> 0.14.2", only: :test, runtime: false},
      {:redix, ">= 0.11.0"}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @repo_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE.txt"
      ]
    ]
  end

  defp package do
    %{
      licenses: ["MIT"],
      links: %{"GitHub" => @repo_url},
      maintainers: ["Adam Mokan"]
    }
  end
end
