import Config

config :video_transcoder,
  port: String.to_integer(System.get_env("PORT") || "4000"),
  s3_bucket: System.get_env("S3_BUCKET"),
  temp_dir: System.get_env("TEMP_DIR") || "/tmp/video_transcoding_#{System.get_env("USER", "default")}"

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION")

config :video_transcoder, VideoTranscoder.Repo,
  database: System.get_env("DATABASE_NAME"),
  username: System.get_env("DATABASE_USER"),
  password: System.get_env("DATABASE_PASSWORD"),
  hostname: System.get_env("DATABASE_HOST"),
  port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"),
  # migration_lock: false,
  pool_size: 10,
  # ssl: true,
  # ssl_opts: [
  #   verify: :verify_none,
  #   server_name_indication: :disable,
  #   secure_renegotiate: false
  # ],
  timeout: 15_000,
  connect_timeout: 10_000,
  handshake_timeout: 10_000,
  show_sensitive_data_on_connection_error: true

config :video_transcoder, ecto_repos: [VideoTranscoder.Repo]

config :prometheus, VideoTranscoder.PrometheusInstrumenter,
  labels: [:method, :status_class, :status],
  duration_buckets: [10, 100, 1_000, 10_000, 100_000, 300_000, 500_000, 750_000, 1_000_000, 1_500_000, 3_000_000],
  registry: :default,
  duration_unit: :microseconds
