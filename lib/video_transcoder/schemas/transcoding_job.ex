defmodule VideoTranscoder.Schemas.TranscodingJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "transcoding_jobs" do
    field :job_id, :string
    field :source_path, :string
    field :target_codec, :string
    field :target_container, :string
    field :source_codec, :string
    field :source_container, :string
    field :output_url, :string
    field :duration_seconds, :integer
    field :status, :string, default: "pending"
    field :error_message, :string
    field :gpu_used, :string
    field :quality_preset, :string
    field :bitrate, :integer
    field :file_size_bytes, :integer
    field :source_duration, :decimal
    field :source_bitrate, :integer
    field :source_width, :integer
    field :source_height, :integer
    field :created_by, :integer

    timestamps()
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :job_id, :source_path, :target_codec, :target_container,
      :source_codec, :source_container, :output_url, :duration_seconds,
      :status, :error_message, :gpu_used, :quality_preset, :bitrate,
      :file_size_bytes, :source_duration, :source_bitrate,
      :source_width, :source_height, :created_by
    ])
    |> validate_required([:job_id, :source_path, :target_codec, :target_container])
    |> unique_constraint(:job_id)
  end
end
