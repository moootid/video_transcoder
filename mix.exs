defmodule VideoTranscoder.MixProject do
  use Mix.Project

  def project do
    [
      app: :video_transcoder,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {VideoTranscoder.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},

      # AWS dependencies
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.24"},
      {:sweet_xml, "~> 0.7.5"},

      # CockroachDB (PostgreSQL) dependencies
      {:postgrex, "~> 0.20.0"},
      {:ecto_sql, "~> 3.13"},
      {:ecto, "~> 3.13"},

      # Prometheus dependencies
      {:prometheus_ex, "~> 3.1"},
      {:prometheus_plugs, "~> 1.1"},
      {:prometheus_process_collector, "~> 1.6"},

      # Utilities
      {:elixir_uuid, "~> 1.2"},
      {:temp, "~> 0.4.9"}
    ]
  end
end
