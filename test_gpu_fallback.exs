#!/usr/bin/env elixir

# Test script to verify GPU detection fallback behavior
# This simulates a Kubernetes environment without GPU tools

Mix.install([])

# Mock System.cmd to simulate missing GPU tools
defmodule MockSystem do
  def cmd("nvidia-smi", _args, _opts), do: raise(ErlangError, original: :enoent)
  def cmd("rocm-smi", _args, _opts), do: raise(ErlangError, original: :enoent)
  def cmd("lspci", _args, _opts), do: {"00:02.0 Audio device: Intel Corporation Device 7abc\n00:1f.3 SMBus: Intel Corporation Device 7ac3", 0}
end

# Copy the GpuDetector module with mocked System calls
defmodule TestGpuDetector do
  require Logger

  def detect_available_gpus do
    %{
      nvidia: detect_nvidia_gpu(),
      amd: detect_amd_gpu(),
      intel: detect_intel_gpu()
    }
  end

  def get_best_gpu_option(available_gpus) do
    cond do
      available_gpus.nvidia.available -> :nvidia
      available_gpus.amd.available -> :amd
      available_gpus.intel.available -> :intel
      true -> :cpu
    end
  end

  defp detect_nvidia_gpu do
    try do
      case MockSystem.cmd("nvidia-smi", ["-L"], stderr_to_stdout: true) do
        {output, 0} ->
          gpu_count = output |> String.split("\n") |> Enum.count(& String.contains?(&1, "GPU"))
          Logger.info("Detected #{gpu_count} NVIDIA GPU(s)")
          %{available: true, count: gpu_count, type: "nvidia"}
        _ ->
          %{available: false, count: 0, type: "nvidia"}
      end
    rescue
      ErlangError ->
        # nvidia-smi not found
        %{available: false, count: 0, type: "nvidia"}
    end
  end

  defp detect_amd_gpu do
    try do
      case MockSystem.cmd("rocm-smi", ["-l"], stderr_to_stdout: true) do
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
      case MockSystem.cmd("lspci", [], stderr_to_stdout: true) do
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
      case MockSystem.cmd("lspci", [], stderr_to_stdout: true) do
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

# Test the GPU detection
IO.puts("Testing GPU detection in a simulated Kubernetes environment...")

available_gpus = TestGpuDetector.detect_available_gpus()
best_option = TestGpuDetector.get_best_gpu_option(available_gpus)

IO.puts("Available GPUs: #{inspect(available_gpus)}")
IO.puts("Best GPU option: #{best_option}")

if best_option == :cpu do
  IO.puts("✅ SUCCESS: Correctly falls back to CPU when no GPUs are available")
else
  IO.puts("❌ FAILURE: Should have fallen back to CPU")
end
