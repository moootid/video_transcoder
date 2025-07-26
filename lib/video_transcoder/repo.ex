defmodule VideoTranscoder.Repo do
  use Ecto.Repo,
    otp_app: :video_transcoder,
    adapter: Ecto.Adapters.Postgres
end
