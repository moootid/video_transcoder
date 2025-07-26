defmodule VideoTranscoder.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Setup temp directory
    setup_temp_directory()

    # Setup Prometheus
    VideoTranscoder.PrometheusInstrumenter.setup()
    VideoTranscoder.PrometheusExporter.setup()
    # Detect available GPUs at startup
    available_gpus = VideoTranscoder.GpuDetector.detect_available_gpus()
    Logger.info("Available GPUs: #{inspect(available_gpus)}")
    children = [
      # Database
      VideoTranscoder.Repo,

      # Web server
      {Plug.Cowboy, scheme: :http, plug: VideoTranscoder.Router, options: [port: Application.get_env(:video_transcoder, :port)]},

      # Task supervisor for transcoding jobs
      {Task.Supervisor, name: VideoTranscoder.TaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VideoTranscoder.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp setup_temp_directory do
    temp_dir = Application.get_env(:video_transcoder, :temp_dir)
    Logger.info("Setting up temp directory: #{temp_dir}")

    case create_temp_directory_with_fallback(temp_dir) do
      {:ok, final_dir} ->
        # Update the config with the final directory used
        Application.put_env(:video_transcoder, :temp_dir, final_dir)
        Logger.info("Temp directory setup successful: #{final_dir}")
      {:error, reason} ->
        Logger.error("Failed to create any temp directory: #{inspect(reason)}")
        raise "Cannot create temp directory: #{inspect(reason)}"
    end
  end

  defp create_temp_directory_with_fallback(primary_dir) do
    case try_create_directory(primary_dir) do
      :ok -> {:ok, primary_dir}
      {:error, _} ->
        # Fallback to user-specific temp directory in /tmp
        fallback_dir = "/tmp/video_transcoding_#{System.get_env("USER", "elixir")}_#{:rand.uniform(10000)}"
        case try_create_directory(fallback_dir) do
          :ok -> {:ok, fallback_dir}
          {:error, _} ->
            # Final fallback to system temp
            system_temp = System.tmp_dir!()
            final_dir = Path.join(system_temp, "video_transcoding_#{:rand.uniform(10000)}")
            case try_create_directory(final_dir) do
              :ok -> {:ok, final_dir}
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  defp try_create_directory(dir) do
    case File.mkdir_p(dir) do
      :ok ->
        case File.chmod(dir, 0o755) do
          :ok ->
            # Test write access
            test_file = Path.join(dir, "test_write_#{:rand.uniform(1000)}")
            case File.write(test_file, "test") do
              :ok ->
                File.rm(test_file)
                :ok
              {:error, reason} -> {:error, reason}
            end
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end
end
