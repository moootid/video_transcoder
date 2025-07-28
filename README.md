# Video Transcoder

A high-performance, GPU-accelerated video transcoding service built with Elixir that supports NVIDIA, AMD, and Intel GPU acceleration with automatic fallback to CPU encoding.

[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-moootid%2Fvideo__transcoder%3Alatest-blue?logo=docker)](https://hub.docker.com/r/moootid/video_transcoder)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-%3E%3D1.18-purple?logo=elixir)](https://elixir-lang.org/)

## Features

### 🚀 High Performance

- **GPU Acceleration**: Automatic detection and utilization of NVIDIA (NVENC), AMD (AMF), and Intel (QSV) hardware encoders
- **Intelligent Fallback**: Automatic fallback chain from GPU to CPU encoders when hardware acceleration is unavailable
- **Concurrent Processing**: Asynchronous job processing with OTP supervision for reliability

### 📹 Video Support

- **Codecs**: H.264, H.265/HEVC, AV1
- **Containers**: MP4, MKV, MOV, AVI
- **Quality Presets**: Low, Medium, High with custom bitrate support
- **Source Analysis**: Automatic detection of source video properties

### ☁️ Cloud Integration

- **S3 Storage**: Direct integration with AWS S3 for input and output files
- **Database Persistence**: PostgreSQL/CockroachDB for job tracking and metadata
- **Prometheus Metrics**: Built-in monitoring and metrics collection
- **RESTful API**: Simple HTTP API for job submission and status tracking

### 🐳 Container Ready

- **Docker Support**: Pre-built Docker images with GPU runtime support
- **Kubernetes Compatible**: Designed for scalable deployment in Kubernetes clusters
- **Health Checks**: Built-in health endpoints for container orchestration

## Quick Start

### Using Docker

```bash
# Pull the image
docker pull moootid/video_transcoder:latest

# Run with environment variables
docker run -p 4000:4000 \
  -e AWS_ACCESS_KEY_ID=your_key \
  -e AWS_SECRET_ACCESS_KEY=your_secret \
  -e AWS_REGION=us-east-1 \
  -e S3_BUCKET=your-bucket \
  -e DATABASE_HOST=your-db-host \
  -e DATABASE_NAME=video_transcoding \
  -e DATABASE_USER=postgres \
  -e DATABASE_PASSWORD=your-password \
  --gpus all \
  moootid/video_transcoder:latest
```

### Using Docker Compose

1. Clone the repository:

```bash
git clone https://github.com/moootid/video_transcoder.git
cd video_transcoder
```

2. Copy and configure environment variables:

```bash
cp .env.example .env
# Edit .env with your configuration
```

3. Start the service:

```bash
docker-compose up -d
```

## API Reference

### Submit Transcoding Job

```http
POST /transcode
Content-Type: application/json

{
  "source_path": "s3://your-bucket/input/video.mp4",
  "target_codec": "h264",
  "target_container": "mp4",
  "quality": "medium",
  "bitrate": 2000,
  "gpu_preference": "auto",
  "created_by": 1
}
```

**Response:**

```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "accepted"
}
```

### Check Job Status

```http
GET /status/{job_id}
```

**Response:**

```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "source_path": "s3://bucket/input.mp4",
  "target_codec": "h264",
  "target_container": "mp4",
  "output_url": "s3://bucket/transcoded/output.mp4",
  "duration_seconds": 45,
  "gpu_used": "nvidia",
  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-15T10:30:45Z"
}
```

### GPU Status

```http
GET /gpu-status
```

**Response:**

```json
{
  "nvidia": {
    "available": true,
    "count": 2,
    "type": "nvidia"
  },
  "amd": {
    "available": false,
    "count": 0,
    "type": "amd"
  },
  "intel": {
    "available": true,
    "count": 1,
    "type": "intel"
  }
}
```

### Health Check

```http
GET /health
```

## Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PORT` | HTTP server port | `4000` | No |
| `AWS_ACCESS_KEY_ID` | AWS access key | - | Yes |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | - | Yes |
| `AWS_REGION` | AWS region | - | Yes |
| `S3_BUCKET` | S3 bucket for files | - | Yes |
| `DATABASE_HOST` | Database hostname | - | Yes |
| `DATABASE_PORT` | Database port | `5432` | No |
| `DATABASE_NAME` | Database name | - | Yes |
| `DATABASE_USER` | Database username | - | Yes |
| `DATABASE_PASSWORD` | Database password | - | Yes |
| `TEMP_DIR` | Temporary directory | `/tmp/video_transcoding_<user>` | No |

### Quality Presets

| Preset | CRF (CPU) | QP (GPU) | Description |
|--------|-----------|----------|-------------|
| `low` | 28 | 28 | Smaller file size, lower quality |
| `medium` | 23 | 23 | Balanced quality and size |
| `high` | 18 | 18 | Higher quality, larger file size |

### GPU Preferences

| Preference | Description |
|------------|-------------|
| `auto` | Automatically select best available GPU (NVIDIA > AMD > Intel > CPU) |
| `nvidia` | Force NVIDIA GPU, fallback to CPU if unavailable |
| `amd` | Force AMD GPU, fallback to CPU if unavailable |
| `intel` | Force Intel GPU, fallback to CPU if unavailable |
| `cpu` | Force CPU encoding |

## Development

### Prerequisites

- Elixir >= 1.18
- Erlang/OTP >= 26
- PostgreSQL
- FFmpeg with GPU support (optional)
- Docker (optional)

### Local Setup

1. Install dependencies:

```bash
mix deps.get
```

2. Set up database:

```bash
mix ecto.setup
```

3. Start the application:

```bash
mix run --no-halt
```

### Testing

Run the test suite:

```bash
mix test
```

Test GPU detection:

```bash
./test_gpu_fallback.exs
```

Test encoder availability:

```bash
./test_encoder_fallback.exs
```

Test database connection:

```bash
./test_db_connection.exs
```

## Monitoring

The service includes built-in Prometheus metrics available at `/metrics`:

### Key Metrics

- `transcoding_jobs_total` - Total transcoding jobs by codec, container, GPU, and status
- `transcoding_duration_seconds` - Job duration histograms
- `active_transcoding_jobs` - Current active jobs gauge
- `gpu_usage_total` - GPU usage counters by type
- `http_requests_total` - HTTP request counters

### Example Prometheus Queries

```promql
# Average transcoding time by GPU type
rate(transcoding_duration_seconds_sum[5m]) / rate(transcoding_duration_seconds_count[5m])

# Job success rate
rate(transcoding_jobs_total{status="success"}[5m]) / rate(transcoding_jobs_total[5m])

# Current queue depth
active_transcoding_jobs
```

## Architecture

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   HTTP Client   │───▶│  Video Transcoder │───▶│   S3 Storage    │
└─────────────────┘    │     Service      │    └─────────────────┘
                       └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   PostgreSQL    │    │   Prometheus    │
                       │    Database     │    │    Metrics      │
                       └─────────────────┘    └─────────────────┘
```

### Components

- **Router** (`VideoTranscoder.Router`) - HTTP request handling
- **TranscodeHandler** - Core transcoding logic and job management
- **GpuDetector** - Hardware detection and GPU selection
- **PrometheusInstrumenter** - Metrics collection and export
- **Repo** - Database operations and job persistence

## Deployment

### Kubernetes

Example deployment with GPU support:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: video-transcoder
spec:
  replicas: 3
  selector:
    matchLabels:
      app: video-transcoder
  template:
    metadata:
      labels:
        app: video-transcoder
    spec:
      containers:
      - name: video-transcoder
        image: moootid/video_transcoder:latest
        ports:
        - containerPort: 4000
        env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: aws-secrets
              key: access-key-id
        # ... other environment variables
        resources:
          limits:
            nvidia.com/gpu: 1
        volumeMounts:
        - name: tmp-storage
          mountPath: /tmp/transcoding
      volumes:
      - name: tmp-storage
        emptyDir: {}
```

### Scaling Considerations

- **Horizontal Scaling**: Multiple instances can process jobs concurrently
- **GPU Resources**: Ensure adequate GPU resources per pod
- **Storage**: Consider shared storage for large temporary files
- **Database**: Use connection pooling for database efficiency

## Troubleshooting

### Common Issues

1. **GPU not detected**: Ensure proper GPU drivers and tools are installed
2. **Permission errors**: Check temp directory permissions and ownership
3. **S3 upload failures**: Verify AWS credentials and bucket permissions
4. **Database connection**: Check database credentials and network connectivity

### Debug Mode

Enable debug logging by setting the log level:

```bash
export ELIXIR_LOG_LEVEL=debug
```

### Encoder Fallback Testing

The service includes comprehensive fallback logic. Test with:

```bash
# Test GPU detection in simulated Kubernetes environment
./test_gpu_fallback.exs

# Test encoder availability
./test_encoder_fallback.exs
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


---

Built with ❤️ using [Elixir](https://elixir-lang.org/) and [OTP](https://www.erlang.org/)
