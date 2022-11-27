defmodule OffBroadwayRedis.MixProject do
  use Mix.Project

  @app_name :off_broadway_redis
  @version "0.4.3"
  @description "An opinionated Redis list connector for Broadway"
  @repo_url "https://github.com/amokan/off_broadway_redis"

  def project do
    [
      app: @app_name,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      name: "OffBroadwayRedis",
      description: @description,
      package: package(),
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.6.7", only: [:dev, :test], runtime: false},
      {:broadway, "~> 1.0.5"},
      {:ex_doc, "~> 0.29.1", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.15.0", only: [:test], runtime: false},
      {:mix_audit, "~> 2.0.2", only: [:dev, :test], runtime: false},
      {:redix, "1.2.0"}
    ]
  end

  defp aliases do
    [
      bump: ["run priv/bump_version.exs"]
    ]
  end
end
