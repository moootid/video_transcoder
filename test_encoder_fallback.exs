#!/usr/bin/env elixir

# Test script to verify encoder fallback functionality
defmodule EncoderTest do
  def check_encoder_availability(encoder_name) do
    case System.cmd("ffmpeg", ["-hide_banner", "-encoders"], stderr_to_stdout: true) do
      {output, 0} ->
        available = String.contains?(output, encoder_name)
        IO.puts("Encoder #{encoder_name}: #{if available, do: "AVAILABLE", else: "NOT AVAILABLE"}")
        available
      {_output, _code} ->
        # If we can't check encoders, assume basic ones are available
        basic_encoders = ["libx264", "libx265", "libaom-av1"]
        available = encoder_name in basic_encoders
        IO.puts("Encoder #{encoder_name}: #{if available, do: "AVAILABLE (assumed)", else: "NOT AVAILABLE (assumed)"}")
        available
    end
  end

  def test_all_encoders do
    encoders_to_test = [
      # NVIDIA encoders
      "h264_nvenc", "hevc_nvenc", "av1_nvenc",
      # AMD encoders
      "h264_amf", "hevc_amf", "av1_amf",
      # Intel encoders
      "h264_qsv", "hevc_qsv", "av1_qsv",
      # CPU encoders
      "libx264", "libx265", "libaom-av1", "libsvtav1"
    ]

    IO.puts("Testing encoder availability:")
    IO.puts("=" <> String.duplicate("=", 40))

    Enum.each(encoders_to_test, &check_encoder_availability/1)
  end
end

EncoderTest.test_all_encoders()
