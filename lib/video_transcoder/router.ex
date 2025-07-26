defmodule VideoTranscoder.Router do
  use Plug.Router
  require Logger
  alias VideoTranscoder.Schemas.TranscodingJob
  alias VideoTranscoder.Repo

  plug Plug.Logger
  plug VideoTranscoder.PrometheusExporter
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/transcode" do
    VideoTranscoder.PrometheusInstrumenter.inc_http_requests("POST", "received")

    case VideoTranscoder.TranscodeHandler.handle_request(conn.body_params) do
      {:ok, job_id} ->
        VideoTranscoder.PrometheusInstrumenter.inc_http_requests("POST", "202")
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(202, Jason.encode!(%{job_id: job_id, status: "accepted"}))

      {:error, reason} ->
        VideoTranscoder.PrometheusInstrumenter.inc_http_requests("POST", "400")
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: reason}))
    end
  end

  get "/status/:job_id" do
    case Repo.get_by(TranscodingJob, job_id: job_id) do
      nil ->
        VideoTranscoder.PrometheusInstrumenter.inc_http_requests("GET", "404")
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Job not found"}))

      job ->
        VideoTranscoder.PrometheusInstrumenter.inc_http_requests("GET", "200")
        response = %{
          job_id: job.job_id,
          status: job.status,
          source_path: job.source_path,
          target_codec: job.target_codec,
          target_container: job.target_container,
          output_url: job.output_url,
          duration_seconds: job.duration_seconds,
          gpu_used: job.gpu_used,
          error_message: job.error_message,
          created_at: job.inserted_at,
          updated_at: job.updated_at
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(response))
    end
  end

  get "/gpu-status" do
    available_gpus = VideoTranscoder.GpuDetector.detect_available_gpus()
    VideoTranscoder.PrometheusInstrumenter.inc_http_requests("GET", "200")

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(available_gpus))
  end

  get "/health" do
    VideoTranscoder.PrometheusInstrumenter.inc_http_requests("GET", "200")
    send_resp(conn, 200, "OK")
  end

  match _ do
    VideoTranscoder.PrometheusInstrumenter.inc_http_requests(conn.method, "404")
    send_resp(conn, 404, "Not Found")
  end
end
