[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/opencreator?utm_medium=integration&utm_source=button&utm_campaign=opencreator)

# OpenCreator (KrillinAI Server) on Railway

One-click Railway template for the **KrillinAI Server** from
[krillinai/OpenCreator](https://github.com/krillinai/OpenCreator) (Apache-2.0):
AI video translation, subtitles and dubbing with a web UI. Upload a video (or
paste a YouTube/Bilibili link), and it transcribes the speech, translates it with
an LLM, writes SRT subtitles, can dub the video with text-to-speech and can burn
the subtitles into a new MP4.

**Version:** KrillinAI Server **v3.3.4** (official release asset
`KrillinAI-Server-3.3.4-linux-x64.tar.gz`, SHA-256
`d95f1711b662aabe553ca40dc1d443fc13b2b488071f9ae471dd14f87d18a026`, checked at build).
Upstream publishes no Docker image, so the `Dockerfile` installs that release on
`debian:trixie-20261104-slim` (pinned by digest) with ffmpeg, Noto CJK fonts,
yt-dlp 2026.10.26, Deno 2.9.8 and Caddy 2.11.9 (all pinned).

The OpenCreator *desktop agent workspace* in the same repo is a local app tied to
a Codex CLI login and is not part of this template.

## What gets deployed

| Service | What it does |
|---|---|
| `OpenCreator` | KrillinAI server on `127.0.0.1:8888`, behind Caddy on `$PORT` with HTTP basic auth. Volume at `/data` holds the config, uploads, task outputs and the yt-dlp cache. |

The KrillinAI server has no login of its own, and its `/api/config` endpoint
returns your API keys, so this template puts Caddy basic auth in front of
everything. Only `/healthz` (Railway's health check) is open.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `OPENAI_API_KEY` | *(you enter it)* | Required. OpenAI key from <https://platform.openai.com/api-keys>, or a key for any OpenAI-compatible API. Used for translation, Whisper transcription and TTS. |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | Change it for another OpenAI-compatible provider. |
| `LLM_MODEL` | `gpt-4o-mini` | Model that translates the subtitles. |
| `TRANSCRIBE_MODEL` | `whisper-1` | Speech-to-text model (`/audio/transcriptions`, needs `verbose_json` timestamps). |
| `TTS_MODEL` | `gpt-4o-mini-tts` | Voice-over model (`/audio/speech`). |
| `ADMIN_USER` | `admin` | Basic-auth user name. |
| `ADMIN_PASSWORD` | generated | Basic-auth password (`${{secret(24)}}`). Find it in the service's Variables tab. |
| `PORT` | `8080` | Public port Caddy listens on. |

Optional, not in the template: `TRANSCRIBE_BASE_URL`/`TRANSCRIBE_API_KEY` and
`TTS_BASE_URL`/`TTS_API_KEY` if speech uses a different provider from the LLM,
`TRANSLATE_PARALLEL_NUM` (default 2) and `FFMPEG_THREADS` (default 2).

Railway variables win for the OpenAI-compatible keys and models on every start.
Everything else you change on the web UI's settings page (other providers such
as Aliyun, MiniMax, Volcengine or Edge TTS, languages, parallelism) is saved in
`/data/config/config.toml` and kept across restarts.

## After deploy

1. Open the service's public URL and log in as `admin` with `ADMIN_PASSWORD`.
2. Upload a video, choose the source and target languages, optionally turn on
   voice-over and subtitle burn-in, and start the task.
3. Download the SRT files, the dubbed audio and the burned-in MP4 from the task
   page. Everything is stored on the `/data` volume.

## Resources

Runs on Railway's Free plan (0.5 GB RAM / 1 vCPU): a 20-second 720p job with
transcription, translation, voice-over and burn-in peaked well under the limit.
ffmpeg is capped at 2 threads (`FFMPEG_THREADS`) because Railway shows the host's
CPU count inside a small service. Long or 1080p+ videos are slower at 1 vCPU and
can use more memory while encoding; give the service 1 GB if you burn in
subtitles on long videos. No GPU and no local Whisper models are used: speech
recognition and TTS go through the API.

YouTube downloads from cloud IPs are often blocked by YouTube; uploading the
file always works.

## Updates

This template builds from this repository. When `main` changes (a new KrillinAI
release or a fix), Railway shows an "update available" notice on your project and
you choose when to apply it. Read [`CHANGELOG.md`](CHANGELOG.md) first: breaking
changes are listed at the top of each entry. Your `/data` volume is kept.
