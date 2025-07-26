#!/usr/bin/env elixir

# Simple script to test database connection
IO.puts("Testing database connection...")

# Print environment variables
IO.puts("Database configuration:")
IO.puts("HOST: #{System.get_env("DATABASE_HOST")}")
IO.puts("PORT: #{System.get_env("DATABASE_PORT", "5432")}")
IO.puts("NAME: #{System.get_env("DATABASE_NAME")}")
IO.puts("USER: #{System.get_env("DATABASE_USER")}")
IO.puts("PASSWORD: #{if System.get_env("DATABASE_PASSWORD"), do: "[REDACTED]", else: "[NOT SET]"}")

# Try to load the application config
Application.load(:video_transcoder)

# Start the necessary applications
Application.ensure_all_started(:ssl)
Application.ensure_all_started(:crypto)
Application.ensure_all_started(:postgrex)

# Try to connect
try do
  {:ok, pid} = Postgrex.start_link(
    hostname: System.get_env("DATABASE_HOST"),
    port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"),
    username: System.get_env("DATABASE_USER"),
    password: System.get_env("DATABASE_PASSWORD"),
    database: System.get_env("DATABASE_NAME"),
    ssl: true,
    ssl_opts: [
      verify: :verify_none,
      server_name_indication: :disable,
      secure_renegotiate: false
    ],
    timeout: 15_000,
    connect_timeout: 10_000,
    handshake_timeout: 10_000
  )

  IO.puts("Direct Postgrex connection successful!")

  # Try a simple query
  case Postgrex.query(pid, "SELECT 1 as test", []) do
    {:ok, result} ->
      IO.puts("Query successful: #{inspect(result)}")
    {:error, error} ->
      IO.puts("Query failed: #{inspect(error)}")
  end

  Postgrex.stop(pid)

rescue
  error ->
    IO.puts("Connection failed: #{inspect(error)}")
end
