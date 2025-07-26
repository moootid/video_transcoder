defmodule VideoTranscoder.TranscodeHandler do
  require Logger
  alias VideoTranscoder.Schemas.TranscodingJob
  alias VideoTranscoder.Repo
  alias Decimal

  @supported_codecs ["h264", "h265", "av1"]
  @supported_containers ["mp4", "mkv", "mov", "avi"]

  def handle_request(params) do
    with {:ok, validated_params} <- validate_params(params),
         job_id <- UUID.uuid4(),
         {:ok, job} <- create_job_record(job_id, validated_params) do

      # Start transcoding job asynchronously
      Task.Supervisor.start_child(VideoTranscoder.TaskSupervisor, fn ->
        process_transcoding_job(job.job_id, validated_params)
      end)

      {:ok, job_id}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_params(%{
    "source_path" => source_path,
    "target_codec" => target_codec,
    "target_container" => target_container,
    "created_by" => created_by
  } = params) when is_binary(source_path) do

    target_codec = String.downcase(target_codec)
    target_container = String.downcase(target_container)

    cond do
      target_codec not in @supported_codecs ->
        {:error, "Unsupported codec: #{target_codec}"}

      target_container not in @supported_containers ->
        {:error, "Unsupported container: #{target_container}"}

      not String.starts_with?(source_path, "s3://") ->
        {:error, "Source path must be an S3 URL"}

      true ->
        {:ok, %{
          source_path: source_path,
          target_codec: target_codec,
          target_container: target_container,
          quality: Map.get(params, "quality", "medium"),
          bitrate: Map.get(params, "bitrate"),
          gpu_preference: Map.get(params, "gpu_preference", "auto"),
          created_by: created_by
        }}
    end
  end

  defp validate_params(_), do: {:error, "Missing required parameters"}

  defp create_job_record(job_id, params) do
    attrs = %{
      job_id: job_id,
      source_path: params.source_path,
      target_codec: params.target_codec,
      target_container: params.target_container,
      quality_preset: params.quality,
      bitrate: params.bitrate,
      status: "pending",
      created_by: params.created_by
    }

    %TranscodingJob{}
    |> TranscodingJob.changeset(attrs)
    |> Repo.insert()
  end

  defp process_transcoding_job(job_id, params) do
    Logger.info("Starting transcoding job #{job_id}")
    VideoTranscoder.PrometheusInstrumenter.inc_active_jobs()

    start_time = System.monotonic_time(:second)

    # Update job status to processing
    update_job_status(job_id, "processing")

    try do
      # Detect available GPUs
      available_gpus = VideoTranscoder.GpuDetector.detect_available_gpus()
      selected_gpu = select_gpu(params.gpu_preference, available_gpus)

      with {:ok, local_input_path} <- download_from_s3(params.source_path),
           {:ok, source_info} <- get_video_info(local_input_path),
           {:ok, local_output_path} <- transcode_video(local_input_path, params, source_info, selected_gpu),
           {:ok, s3_output_url} <- upload_to_s3(local_output_path, params),
           {:ok, file_size} <- File.stat(local_output_path, [:size]),
           :ok <- store_job_result(job_id, params, source_info, s3_output_url, start_time, selected_gpu, file_size.size) do

        cleanup_temp_files([local_input_path, local_output_path])

        duration = System.monotonic_time(:second) - start_time
        VideoTranscoder.PrometheusInstrumenter.observe_transcoding_duration(
          source_info.codec, params.target_codec, selected_gpu, duration
        )
        VideoTranscoder.PrometheusInstrumenter.inc_transcoding_jobs(
          source_info.codec, params.target_codec,
          source_info.container, params.target_container,
          selected_gpu, "success"
        )

        update_job_status(job_id, "completed")
        Logger.info("Transcoding job #{job_id} completed successfully using #{selected_gpu}")
      else
        {:error, reason} ->
          Logger.error("Transcoding job #{job_id} failed: #{inspect(reason)}")
          update_job_status(job_id, "failed", to_string(reason))
          VideoTranscoder.PrometheusInstrumenter.inc_transcoding_jobs(
            "unknown", params.target_codec,
            "unknown", params.target_container,
            "cpu", "error"
          )
      end
    rescue
      error in File.Error ->
        case error do
          %File.Error{reason: :eacces, path: path} ->
            Logger.error("Transcoding job #{job_id} failed due to permission error on path: #{path}")
            update_job_status(job_id, "failed", "Permission denied accessing file: #{path}")
            VideoTranscoder.PrometheusInstrumenter.inc_transcoding_jobs(
              "unknown", params.target_codec,
              "unknown", params.target_container,
              "cpu", "permission_error"
            )

          %File.Error{reason: reason, path: path} ->
            Logger.error("Transcoding job #{job_id} failed due to file error: #{reason} on path: #{path}")
            update_job_status(job_id, "failed", "File error (#{reason}): #{path}")
            VideoTranscoder.PrometheusInstrumenter.inc_transcoding_jobs(
              "unknown", params.target_codec,
              "unknown", params.target_container,
              "cpu", "file_error"
            )
        end

      error ->
        Logger.error("Transcoding job #{job_id} crashed: #{inspect(error)}")
        update_job_status(job_id, "failed", "Job crashed: #{inspect(error)}")
        VideoTranscoder.PrometheusInstrumenter.inc_transcoding_jobs(
          "unknown", params.target_codec,
          "unknown", params.target_container,
          "cpu", "crash"
        )
    after
      VideoTranscoder.PrometheusInstrumenter.dec_active_jobs()
    end
  end

  defp select_gpu("auto", available_gpus) do
    VideoTranscoder.GpuDetector.get_best_gpu_option(available_gpus)
  end

  defp select_gpu(preference, available_gpus) do
    case preference do
      "nvidia" when available_gpus.nvidia.available -> :nvidia
      "amd" when available_gpus.amd.available -> :amd
      "intel" when available_gpus.intel.available -> :intel
      "cpu" -> :cpu
      _ -> VideoTranscoder.GpuDetector.get_best_gpu_option(available_gpus)
    end
  end

  defp update_job_status(job_id, status, error_message \\ nil) do
    job = Repo.get_by(TranscodingJob, job_id: job_id)
    if job do
      attrs = %{status: status}
      attrs = if error_message, do: Map.put(attrs, :error_message, error_message), else: attrs

      job
      |> TranscodingJob.changeset(attrs)
      |> Repo.update()
    end
  end

  defp download_from_s3("s3://" <> path) do
    [bucket | key_parts] = String.split(path, "/", parts: 2)
    key = Enum.join(key_parts, "/")

    temp_dir = Application.get_env(:video_transcoder, :temp_dir)

    # Ensure temp directory exists with proper permissions
    case ensure_temp_directory(temp_dir) do
      :ok ->
        local_path = Path.join(temp_dir, "input_#{UUID.uuid4()}_#{Path.basename(key)}")

        case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
          {:ok, %{body: body}} ->
            case File.write(local_path, body) do
              :ok ->
                {:ok, local_path}
              {:error, reason} ->
                {:error, "Failed to write file to #{local_path}: #{inspect(reason)}"}
            end
          {:error, reason} ->
            {:error, "Failed to download from S3: #{inspect(reason)}"}
        end
      {:error, reason} ->
        {:error, "Failed to create temp directory: #{inspect(reason)}"}
    end
  end

  defp get_video_info(file_path) do
    case System.cmd("ffprobe", [
      "-v", "quiet",
      "-print_format", "json",
      "-show_format",
      "-show_streams",
      file_path
    ]) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, info} ->
            video_stream = Enum.find(info["streams"], & &1["codec_type"] == "video")
            format_info = info["format"]

            {:ok, %{
              codec: video_stream["codec_name"],
              container: format_info["format_name"] |> String.split(",") |> List.first(),
              duration: Decimal.new(format_info["duration"]),
              bitrate: String.to_integer(format_info["bit_rate"]),
              width: video_stream["width"],
              height: video_stream["height"]
            }}
          {:error, _} ->
            {:error, "Failed to parse ffprobe output"}
        end
      {_output, _code} ->
        {:error, "Failed to analyze video file"}
    end
  end

  defp transcode_video(input_path, params, source_info, selected_gpu) do
    temp_dir = Application.get_env(:video_transcoder, :temp_dir)

    case ensure_temp_directory(temp_dir) do
      :ok ->
        output_filename = "output_#{UUID.uuid4()}.#{params.target_container}"
        output_path = Path.join(temp_dir, output_filename)

        ffmpeg_args = build_ffmpeg_args(input_path, output_path, params, source_info, selected_gpu)

        Logger.info("Running FFmpeg with GPU: #{selected_gpu}")
        Logger.debug("FFmpeg args: #{inspect(ffmpeg_args)}")

        case System.cmd("ffmpeg", ffmpeg_args, stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, output_path}
          {output, code} ->
            error_message = parse_ffmpeg_error(output, code)
            Logger.error("FFmpeg failed with code #{code}: #{error_message}")
            Logger.debug("Full FFmpeg output: #{output}")
            {:error, error_message}
        end
      {:error, reason} ->
        {:error, "Failed to create temp directory: #{inspect(reason)}"}
    end
  end

  defp parse_ffmpeg_error(output, code) do
    cond do
      String.contains?(output, "Unknown encoder") ->
        # Extract the encoder name from the error
        case Regex.run(~r/Unknown encoder '([^']+)'/, output) do
          [_, encoder] -> "Encoder '#{encoder}' is not available in this FFmpeg build"
          _ -> "Unknown encoder error"
        end

      String.contains?(output, "No such file or directory") ->
        "Input or output file path error"

      String.contains?(output, "Permission denied") ->
        "Permission denied accessing file"

      String.contains?(output, "Invalid data found") ->
        "Invalid or corrupted input file"

      String.contains?(output, "Operation not permitted") ->
        "GPU operation not permitted - GPU may not be available"

      String.contains?(output, "Device or resource busy") ->
        "GPU device is busy or unavailable"

      code == 1 ->
        "FFmpeg encoding error (exit code 1)"

      true ->
        "Transcoding failed with exit code #{code}"
    end
  end

  defp get_codec_args_with_fallback(target_codec, selected_gpu) do
    # Define encoder preferences in order of preference
    encoder_options = case {target_codec, selected_gpu} do
      # NVIDIA GPU acceleration
      {"h264", :nvidia} -> [
        {"h264_nvenc", ["-c:v", "h264_nvenc", "-preset", "fast"]},
        {"libx264", ["-c:v", "libx264", "-preset", "fast"]}
      ]
      {"h265", :nvidia} -> [
        {"hevc_nvenc", ["-c:v", "hevc_nvenc", "-preset", "fast"]},
        {"libx265", ["-c:v", "libx265", "-preset", "fast"]}
      ]
      {"av1", :nvidia} -> [
        {"av1_nvenc", ["-c:v", "av1_nvenc", "-preset", "fast"]},
        {"libsvtav1", ["-c:v", "libsvtav1", "-preset", "4"]},
        {"libaom-av1", ["-c:v", "libaom-av1", "-cpu-used", "4"]}
      ]

      # AMD GPU acceleration
      {"h264", :amd} -> [
        {"h264_amf", ["-c:v", "h264_amf", "-quality", "speed"]},
        {"libx264", ["-c:v", "libx264", "-preset", "fast"]}
      ]
      {"h265", :amd} -> [
        {"hevc_amf", ["-c:v", "hevc_amf", "-quality", "speed"]},
        {"libx265", ["-c:v", "libx265", "-preset", "fast"]}
      ]
      {"av1", :amd} -> [
        {"av1_amf", ["-c:v", "av1_amf", "-quality", "speed"]},
        {"libsvtav1", ["-c:v", "libsvtav1", "-preset", "4"]},
        {"libaom-av1", ["-c:v", "libaom-av1", "-cpu-used", "4"]}
      ]

      # Intel GPU acceleration
      {"h264", :intel} -> [
        {"h264_qsv", ["-c:v", "h264_qsv", "-preset", "fast"]},
        {"libx264", ["-c:v", "libx264", "-preset", "fast"]}
      ]
      {"h265", :intel} -> [
        {"hevc_qsv", ["-c:v", "hevc_qsv", "-preset", "fast"]},
        {"libx265", ["-c:v", "libx265", "-preset", "fast"]}
      ]
      {"av1", :intel} -> [
        {"av1_qsv", ["-c:v", "av1_qsv", "-preset", "fast"]},
        {"libsvtav1", ["-c:v", "libsvtav1", "-preset", "4"]},
        {"libaom-av1", ["-c:v", "libaom-av1", "-cpu-used", "4"]}
      ]

      # CPU fallback
      {"h264", :cpu} -> [
        {"libx264", ["-c:v", "libx264", "-preset", "fast"]}
      ]
      {"h265", :cpu} -> [
        {"libx265", ["-c:v", "libx265", "-preset", "fast"]}
      ]
      {"av1", :cpu} -> [
        {"libsvtav1", ["-c:v", "libsvtav1", "-preset", "4"]},
        {"libaom-av1", ["-c:v", "libaom-av1", "-cpu-used", "4"]}
      ]

      # Default fallback
      {codec, _} ->
        Logger.warning("Unsupported codec/GPU combination: #{codec}/#{selected_gpu}, falling back to CPU")
        case codec do
          "h264" -> [{"libx264", ["-c:v", "libx264", "-preset", "fast"]}]
          "h265" -> [{"libx265", ["-c:v", "libx265", "-preset", "fast"]}]
          "av1" -> [
            {"libsvtav1", ["-c:v", "libsvtav1", "-preset", "4"]},
            {"libaom-av1", ["-c:v", "libaom-av1", "-cpu-used", "4"]}
          ]
        end
    end

    # Try each encoder option until we find one that's available
    find_available_encoder(encoder_options)
  end

  defp find_available_encoder([{encoder_name, args} | rest]) do
    case check_encoder_availability(encoder_name) do
      true ->
        Logger.info("Using encoder: #{encoder_name}")
        args
      false ->
        Logger.warning("Encoder #{encoder_name} not available, trying next option")
        find_available_encoder(rest)
    end
  end

  defp find_available_encoder([]) do
    Logger.error("No suitable encoder found, falling back to libx264")
    ["-c:v", "libx264", "-preset", "fast"]
  end

  defp check_encoder_availability(encoder_name) do
    case System.cmd("ffmpeg", ["-hide_banner", "-encoders"], stderr_to_stdout: true) do
      {output, 0} ->
        String.contains?(output, encoder_name)
      {_output, _code} ->
        # If we can't check encoders, assume basic ones are available
        encoder_name in ["libx264", "libx265", "libaom-av1"]
    end
  end

  defp cpu_encoder?(codec_args) do
    # Check if the codec arguments contain CPU-only encoders
    codec_string = Enum.join(codec_args, " ")
    Enum.any?(["libx264", "libx265", "libaom-av1", "libsvtav1"], fn encoder ->
      String.contains?(codec_string, encoder)
    end)
  end

  defp build_ffmpeg_args(input_path, output_path, params, _source_info, selected_gpu) do
    base_args = ["-i", input_path, "-y"]

    # Get codec arguments with fallback support
    codec_args = get_codec_args_with_fallback(params.target_codec, selected_gpu)

    # Determine if we're using a CPU encoder by checking the codec args
    is_cpu_encoder = cpu_encoder?(codec_args)

    quality_args = case params.quality do
      "low" -> if is_cpu_encoder, do: ["-crf", "28"], else: ["-qp", "28"]
      "medium" -> if is_cpu_encoder, do: ["-crf", "23"], else: ["-qp", "23"]
      "high" -> if is_cpu_encoder, do: ["-crf", "18"], else: ["-qp", "18"]
      _ -> if is_cpu_encoder, do: ["-crf", "23"], else: ["-qp", "23"]
    end

    bitrate_args = if params.bitrate do
      ["-b:v", "#{params.bitrate}k", "-maxrate", "#{round(params.bitrate * 1.2)}k", "-bufsize", "#{params.bitrate * 2}k"]
    else
      []
    end

    audio_args = ["-c:a", "aac", "-b:a", "128k"]

    # Add GPU-specific arguments only if we're actually using a GPU encoder
    gpu_args = get_gpu_args(selected_gpu, codec_args)

    base_args ++ gpu_args ++ codec_args ++ quality_args ++ bitrate_args ++ audio_args ++ [output_path]
  end

  defp get_gpu_args(selected_gpu, codec_args) do
    codec_string = Enum.join(codec_args, " ")

    cond do
      selected_gpu == :nvidia and String.contains?(codec_string, "_nvenc") ->
        ["-gpu", "0"]
      selected_gpu == :intel and String.contains?(codec_string, "_qsv") ->
        ["-init_hw_device", "qsv=hw", "-filter_hw_device", "hw"]
      selected_gpu == :amd and String.contains?(codec_string, "_amf") ->
        []
      true ->
        # Not using GPU encoder or CPU fallback
        []
    end
  end

  defp upload_to_s3(local_path, params) do
    bucket = Application.get_env(:video_transcoder, :s3_bucket)
    key = "transcoded/#{UUID.uuid4()}.#{params.target_container}"

    case File.read(local_path) do
      {:ok, file_content} ->
        case ExAws.S3.put_object(bucket, key, file_content) |> ExAws.request() do
          {:ok, _} ->
            {:ok, "s3://#{bucket}/#{key}"}
          {:error, reason} ->
            {:error, "Failed to upload to S3: #{inspect(reason)}"}
        end
      {:error, reason} ->
        {:error, "Failed to read output file: #{inspect(reason)}"}
    end
  end

  defp store_job_result(job_id, _params, source_info, output_url, start_time, selected_gpu, file_size) do
    end_time = System.monotonic_time(:second)
    duration = end_time - start_time

    job = Repo.get_by(TranscodingJob, job_id: job_id)
    if job do
      attrs = %{
        source_codec: source_info.codec,
        source_container: source_info.container,
        output_url: output_url,
        duration_seconds: duration,
        status: "completed",
        gpu_used: to_string(selected_gpu),
        file_size_bytes: file_size,
        source_duration: source_info.duration,
        source_bitrate: source_info.bitrate,
        source_width: source_info.width,
        source_height: source_info.height
      }

      job
      |> TranscodingJob.changeset(attrs)
      |> Repo.update()
    end

    :ok
  end

  defp cleanup_temp_files(files) do
    Enum.each(files, fn file ->
      if File.exists?(file) do
        File.rm!(file)
      end
    end)
  end

  defp ensure_temp_directory(temp_dir) do
    case File.mkdir_p(temp_dir) do
      :ok ->
        # Set proper permissions (read, write, execute for owner and group)
        case File.chmod(temp_dir, 0o755) do
          :ok -> :ok
          {:error, reason} ->
            Logger.warning("Could not set permissions on temp directory #{temp_dir}: #{inspect(reason)}")
            :ok  # Continue anyway, mkdir_p succeeded
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
end
