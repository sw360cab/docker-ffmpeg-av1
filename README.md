# Docker FFmpeg AV1

Containerized fully static compiled FFmpeg binary with AOM AV1 Codec and
provided with a sample containerized Node.js application leveraging FFmpeg to process videos.

## Build and run

### Building FFMpeg

```bash
docker build -t ffmpeg-exec -f ffmpeg.Dockerfile .
```

### Sampel usage

```bash
docker build -t node-media-transcoder .
docker run --rm -v "${PWD}/data:/data" node-media-transcoder -i /data/sample_0.mp4 -c av1
```

## Docker Compose

### Building FFMpeg

* Force build in order

```bash
  DOCKER_BUILDKIT=0 docker-compose build
```

* Alternatively build `ffmpeg` beforehand

```bash
docker compose build ffmpeg
docker compose build
```

### Running in Node.js application

```bash
docker compose run media-transcoder -i /data/sample_0.mp4 -c av1
```
