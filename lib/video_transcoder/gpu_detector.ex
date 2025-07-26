defmodule VideoTranscoder.GpuDetector do
  require Logger

  @doc """
  Detects available GPU acceleration options
  Returns a map with available GPU types and their capabilities
  """
  def detect_available_gpus do
    %{
      nvidia: detect_nvidia_gpu(),
      amd: detect_amd_gpu(),
      intel: detect_intel_gpu()
    }
  end

  def get_best_gpu_option(available_gpus) do
    cond do
      available_gpus.nvidia -> :nvidia
      available_gpus.amd -> :amd
      available_gpus.intel -> :intel
      true -> :cpu
    end
  end

  defp detect_nvidia_gpu do
    case System.cmd("nvidia-smi", ["-L"], stderr_to_stdout: true) do
      {output, 0} ->
        gpu_count = output |> String.split("\n") |> Enum.count(& String.contains?(&1, "GPU"))
        Logger.info("Detected #{gpu_count} NVIDIA GPU(s)")
        %{available: true, count: gpu_count, type: "nvidia"}
      _ ->
        %{available: false, count: 0, type: "nvidia"}
    end
  end

  defp detect_amd_gpu do
    try do
      case System.cmd("rocm-smi", ["-l"], stderr_to_stdout: true) do
        {output, 0} ->
          gpu_count = output |> String.split("\n") |> Enum.count(& String.contains?(&1, "GPU"))
          Logger.info("Detected #{gpu_count} AMD GPU(s)")
          %{available: true, count: gpu_count, type: "amd"}
        _ ->
          fallback_amd_detection()
      end
    rescue
      ErlangError ->
        # rocm-smi not found, try fallback detection
        fallback_amd_detection()
    end
  end

  defp fallback_amd_detection do
    # Fallback: check for AMD GPU in lspci
    try do
      case System.cmd("lspci", [], stderr_to_stdout: true) do
        {output, 0} ->
          if String.contains?(String.downcase(output), "amd") do
            Logger.info("Detected AMD GPU via lspci")
            %{available: true, count: 1, type: "amd"}
          else
            %{available: false, count: 0, type: "amd"}
          end
        _ ->
          %{available: false, count: 0, type: "amd"}
      end
    rescue
      ErlangError ->
        %{available: false, count: 0, type: "amd"}
    end
  end

  defp detect_intel_gpu do
    try do
      case System.cmd("lspci", [], stderr_to_stdout: true) do
        {output, 0} ->
          if String.contains?(String.downcase(output), "intel") and String.contains?(String.downcase(output), "graphics") do
            gpu_count = output |> String.split("\n") |> Enum.count(&(String.contains?(String.downcase(&1), "intel") and String.contains?(String.downcase(&1), "graphics")))
            Logger.info("Detected #{gpu_count} Intel GPU(s)")
            %{available: true, count: gpu_count, type: "intel"}
          else
            %{available: false, count: 0, type: "intel"}
          end
        _ ->
          %{available: false, count: 0, type: "intel"}
      end
    rescue
      ErlangError ->
        %{available: false, count: 0, type: "intel"}
    end
  end
end
