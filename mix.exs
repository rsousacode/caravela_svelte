defmodule CaravelaSvelte.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/rsousacode/caravela_svelte"

  def project do
    [
      app: :caravela_svelte,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),

      # Hex
      description:
        "Svelte + Phoenix with pluggable render modes — LiveView WebSocket or Inertia-style HTTP.",
      package: package(),

      # Docs
      name: "CaravelaSvelte",
      docs: [
        name: "CaravelaSvelte",
        source_ref: "v#{@version}",
        source_url: @repo_url,
        homepage_url: @repo_url,
        main: "readme",
        extras: [
          "README.md": [title: "CaravelaSvelte"],
          "docs/render_modes.md": [title: "Render modes"],
          "docs/getting_started.md": [title: "Getting started"],
          "docs/live.md": [title: ":live mode"],
          "docs/rest.md": [title: ":rest mode"],
          "docs/caravela.md": [title: "Caravela integration"],
          "NOTICE.md": [title: "Notice"],
          "UPSTREAM.md": [title: "Upstream Sync"]
        ],
        groups_for_extras: [
          Guides: ~r/docs\/.+/
        ]
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Rui Sousa"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @repo_url,
        "Upstream (live_svelte)" => "https://github.com/woutdp/live_svelte"
      },
      files:
        ~w(assets/js assets/copy lib docs mix.exs package.json .formatter.exs LICENSE NOTICE.md UPSTREAM.md README.md CHANGELOG.md)
    ]
  end

  def application do
    [extra_applications: [:logger, :inets]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, ">= 1.7.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, ">= 3.3.1"},
      {:phoenix_vite, "~> 0.4"},
      {:jsonpatch, "~> 2.3"},
      {:nodejs, "~> 3.1"},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:jason, "~> 1.2", optional: true},
      {:ecto, ">= 3.0.0", optional: true},
      {:phoenix_ecto, ">= 4.0.0", optional: true},
      {:igniter, "~> 0.6", optional: true},

      # dev / test
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
