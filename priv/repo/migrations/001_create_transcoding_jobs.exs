defmodule VideoTranscoder.Repo.Migrations.CreateTranscodingJobs do
  use Ecto.Migration

  def change do
    # Enable UUID extension for PostgreSQL
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"", "DROP EXTENSION IF EXISTS \"uuid-ossp\""

    create table(:transcoding_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :job_id, :string, null: false, size: 255
      add :source_path, :text, null: false
      add :target_codec, :string, null: false, size: 50
      add :target_container, :string, null: false, size: 50
      add :source_codec, :string, size: 50
      add :source_container, :string, size: 50
      add :output_url, :text
      add :duration_seconds, :integer
      add :status, :string, default: "pending", size: 50
      add :error_message, :text
      add :gpu_used, :string, size: 100
      add :quality_preset, :string, size: 50
      add :bitrate, :integer
      add :file_size_bytes, :bigint
      add :source_duration, :decimal, precision: 10, scale: 3
      add :source_bitrate, :integer
      add :source_width, :integer
      add :source_height, :integer
      add :created_by, :integer, size: 100

      timestamps()
    end

    # Add constraints
    create constraint(:transcoding_jobs, :status_must_be_valid,
           check: "status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')")

    create constraint(:transcoding_jobs, :bitrate_positive,
           check: "bitrate IS NULL OR bitrate > 0")

    create constraint(:transcoding_jobs, :file_size_positive,
           check: "file_size_bytes IS NULL OR file_size_bytes > 0")

    create constraint(:transcoding_jobs, :duration_positive,
           check: "duration_seconds IS NULL OR duration_seconds > 0")

    create constraint(:transcoding_jobs, :dimensions_positive,
           check: "(source_width IS NULL OR source_width > 0) AND (source_height IS NULL OR source_height > 0)")

    # Indexes
    create unique_index(:transcoding_jobs, [:job_id])
    create index(:transcoding_jobs, [:status])
    create index(:transcoding_jobs, [:inserted_at])
    create index(:transcoding_jobs, [:status, :inserted_at])
    create index(:transcoding_jobs, [:target_codec])
    create index(:transcoding_jobs, [:gpu_used])
  end
end
