defmodule CommandKit.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/123fahrschule/command_kit"

  def project do
    [
      app: :command_kit,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      aliases: aliases(),
      consolidate_protocols: Mix.env() != :test
    ]
  end

  def cli do
    [
      preferred_envs: [
        check: :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:telemetry, "~> 1.0"},
      {:ecto, "~> 3.13", optional: true},
      {:oban, "~> 2.18", optional: true},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: ["compile --warnings-as-errors", "format --check-formatted", "test"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "docs/guides/commands.md",
        "docs/guides/metadata.md",
        "docs/guides/context.md",
        "docs/guides/pipelines-and-middleware.md",
        "docs/guides/async.md",
        "docs/guides/testing.md",
        "docs/guides/migration.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("docs/guides/*.md")
      ],
      groups_for_modules: [
        Core: [
          CommandKit,
          CommandKit.Core.Command,
          CommandKit.Ecto.Command,
          CommandKit.Bus,
          CommandKit.Context,
          CommandKit.Pipeline
        ],
        Middleware: ~r/CommandKit\.Middleware/,
        Async: ~r/CommandKit\.Async/
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
