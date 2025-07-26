defmodule VideoTranscoder.PrometheusInstrumenter do
  use Prometheus.Metric

  def setup do
    Counter.declare(
      name: :transcoding_jobs_total,
      help: "Total number of transcoding jobs",
      labels: [:codec_from, :codec_to, :container_from, :container_to, :gpu_used, :status]
    )

    Histogram.declare(
      name: :transcoding_duration_seconds,
      help: "Transcoding job duration",
      labels: [:codec_from, :codec_to, :gpu_used],
      buckets: [1, 5, 10, 30, 60, 120, 300, 600, 1200, 1800, 3600]
    )

    Gauge.declare(
      name: :active_transcoding_jobs,
      help: "Number of active transcoding jobs"
    )

    Counter.declare(
      name: :gpu_usage_total,
      help: "Total GPU usage by type",
      labels: [:gpu_type]
    )

    Counter.declare(
      name: :http_requests_total,
      help: "Total HTTP requests",
      labels: [:method, :status]
    )
  end

  def inc_transcoding_jobs(codec_from, codec_to, container_from, container_to, gpu_used, status) do
    Counter.inc(
      name: :transcoding_jobs_total,
      labels: [codec_from, codec_to, container_from, container_to, gpu_used, status]
    )
  end

  def observe_transcoding_duration(codec_from, codec_to, gpu_used, duration) do
    Histogram.observe(
      name: :transcoding_duration_seconds,
      labels: [codec_from, codec_to, gpu_used],
      value: duration
    )
  end

  def inc_active_jobs do
    Gauge.inc(name: :active_transcoding_jobs)
  end

  def dec_active_jobs do
    Gauge.dec(name: :active_transcoding_jobs)
  end

  def inc_gpu_usage(gpu_type) do
    Counter.inc(name: :gpu_usage_total, labels: [gpu_type])
  end

  def inc_http_requests(method, status) do
    Counter.inc(name: :http_requests_total, labels: [method, status])
  end
end
