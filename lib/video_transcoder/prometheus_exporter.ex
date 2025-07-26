defmodule VideoTranscoder.PrometheusExporter do
  use Prometheus.PlugExporter

  def setup_process_collector do
    Prometheus.Registry.register_collector(:prometheus_process_collector)
  end
end
