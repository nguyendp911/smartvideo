# ViePN Gemini AI Gateway (Cloudflare Worker)

Runs the Gemini API server-side. **Never put GEMINI_API_KEY in iOS source code, Info.plist, workflow logs or UserDefaults.**

## Deploy

1. Install Node.js and run `npm install` in this directory.
2. Configure `wrangler.toml` with your private Worker name, then deploy using `npm run deploy`.
3. In the Cloudflare dashboard, set the two **encrypted Worker secrets** `GEMINI_API_KEY` (from Google AI Studio) and `GATEWAY_ACCESS_TOKEN` (generate a long random token, distinct from the Gemini API key).
4. Optional variable `GEMINI_MODEL` defaults to `gemini-2.5-flash`; change it if no longer supported by your account.
5. In ViePN Smart Video > **AI** > Gemini, enter your HTTPS Worker base URL and its **gateway access token**, not the Gemini API key. The token is saved in iOS Keychain.

## Endpoint

`POST /v1/revoice` accepts 1–100 timed transcript segments. It sends **text only** to Gemini, never audio/video/photos. It returns one rewritten segment for each original id with the same timestamps. Sample request:

```json
{"style":"Kể chuyện","language":"vi","instructions":"Giọng nhẹ nhàng","segments":[{"id":0,"start":0,"end":3,"text":"Xin chào các bạn"}]}
```

Headers: `Authorization: Bearer <GATEWAY_ACCESS_TOKEN>` and `Content-Type: application/json`.

## Privacy, safety and limits

- Keep the Worker URL and bearer token private. For a public multi-user product add per-user authentication, rate limits, quotas, billing and abuse detection; this is a **single-owner private gateway**, not a production public API.
- Audio recognition happens through Apple Speech using the existing on-device / explicit Apple-service consent settings. Only corrected transcript text goes to Google Gemini.
- Transcription, translation and rewriting can introduce errors. Review names, numbers, timing and meaning before publishing.
- Replacing video audio mutes the **whole source track**, potentially including original music or ambient sounds. Source separation / voice-only removal is **not** implemented.
- Rewritten subtitles retain approximate source timestamps. A whole-track iOS TTS voice is **not word-aligned** to those timestamps.
- This first version does **not** upload video to Gemini, infer visual events, clone voices, generate a native Gemini speech waveform or erase hardcoded subtitles burned into video frames.

## Local checks
`npm run check` TypeScript validation; GitHub iOS CI remains the authoritative Swift build.
