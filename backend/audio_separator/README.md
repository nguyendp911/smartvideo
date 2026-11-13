# ViePN AI Voice Separation (optional private service)

Demucs htdemucs separates a clip's vocal stem and the accompaniment (music/ambient audio).
This is an **approximation**, not guaranteed flawless speech removal; music with vocals
and strong echoes may produce artifacts.

## Deployment

- Requires a server with sufficient RAM/CPU or GPU. CPU processing can be very slow.
- Install Docker, build: `docker build -t viepn-separator .`.
- Set a long random `SEPARATOR_ACCESS_TOKEN` secret in your deployment.
- Place it behind HTTPS and authentication. Example on a private machine:
  `docker run --rm -p 127.0.0.1:8080:8080 -e SEPARATOR_ACCESS_TOKEN=<secure-token> viepn-separator`.
- Configure a reverse proxy to provide HTTPS; never publish the raw HTTP port.
- On first request, Demucs may download its model weights. This requires outbound Internet.
- Health endpoint: `GET /health`.
- Authenticated endpoint: `POST /v1/remove-vocals`; multipart key `audio`, return
  `audio/mp4` m4a accompaniment without detected vocals.
- Maximum duration 600s, 60MB. One concurrent separation per worker.
- The uploaded audio is processed in a temporary directory and deleted after response.
  Disable application/proxy request-body logging or permanent storage.

## Privacy and user controls

Audio leaves the iPhone ONLY when the user explicitly triggers separation.
Do not advertise this as fully local AI processing.
The original source track remains untouched. The iOS integration must offer
review/approval before muting that track and replacing its background audio.

The service does not handle text-to-speech or video upload. Gemini API key
is never sent here. No automatic voice cloning is performed.
