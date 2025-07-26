FROM elixir:1.18

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        git \
        netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# Install NVIDIA drivers and tools (if available)
RUN apt-get install -y --no-install-recommends \
        nvidia-driver \
        nvidia-smi || true

# Install AMD ROCm tools (if available)
RUN apt-get install -y --no-install-recommends \
        rocm-smi || true

WORKDIR /app

# Copy dependency files
COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix deps.compile

# Copy source code
COPY . .

# Compile the application
RUN mix compile

# Create temp directory
RUN mkdir -p /tmp/transcoding

EXPOSE 4000

CMD ["mix", "run", "--no-halt"]