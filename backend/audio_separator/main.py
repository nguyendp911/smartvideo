"""Private GPU/CPU audio stem separator for ViePN Smart Video.

Run behind HTTPS with a long random API token. The service accepts audio
ONLY following an explicit upload action in the iOS app.
"""
from __future__ import annotations

import asyncio
import hmac
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

app = FastAPI(title="ViePN Voice Separation API", docs_url=None, redoc_url=None)
LOCK = asyncio.Semaphore(1)
MAX_BYTES = 60 * 1024 * 1024
MAX_SECONDS = 600


def authorized(header: str | None) -> None:
    token = os.environ.get("SEPARATOR_ACCESS_TOKEN", "")
    if not token or not header or not hmac.compare_digest(header, f"Bearer {token}"):
        raise HTTPException(status_code=401, detail="Unauthorized")


def run_command(args: list[str], timeout: int) -> None:
    process = subprocess.run(
        args, timeout=timeout, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE, check=False,
    )
    if process.returncode:
        raise RuntimeError(process.stderr.decode("utf-8", "replace")[-1200:])


def convert(root: Path, source: Path) -> Path:
    duration = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "format=duration", "-of", "default=noprint_wrappers=1:nokey=1",
         str(source)],
        capture_output=True, text=True, timeout=20, check=True,
    )
    seconds = float(duration.stdout.strip())
    if not 0.1 < seconds <= MAX_SECONDS:
        raise ValueError("Audio must be between 0.1s and 600s")
    stems = root / "stems"
    run_command([
        sys.executable, "-m", "demucs",
        "--two-stems", "vocals", "-n", "htdemucs",
        "--out", str(stems), str(source),
    ], timeout=1200)
    candidate = stems / "htdemucs" / source.stem / "no_vocals.wav"
    if not candidate.exists():
        raise RuntimeError("No accompaniment stem generated")
    target = root / "background.m4a"
    run_command([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(candidate), "-vn", "-c:a", "aac",
        "-b:a", "192k", str(target),
    ], timeout=120)
    return target


@app.get("/health")
async def health():
    return {"status": "ok", "engine": "demucs-htdemucs", "max_seconds": MAX_SECONDS}


@app.post("/v1/remove-vocals")
async def remove_vocals(
    audio: UploadFile = File(...),
    authorization: str | None = Header(default=None),
):
    authorized(authorization)
    if audio.content_type not in (
        "audio/mp4", "audio/m4a", "audio/x-m4a",
        "audio/mpeg", "audio/wav", "application/octet-stream",
    ):
        raise HTTPException(415, "Upload an audio file, not a video")
    async with LOCK:
        directory = tempfile.TemporaryDirectory(prefix="viepns-stems-")
        root = Path(directory.name)
        input_file = root / "voice.m4a"
        try:
            size = 0
            with input_file.open("wb") as sink:
                while chunk := await audio.read(1024 * 1024):
                    size += len(chunk)
                    if size > MAX_BYTES:
                        raise HTTPException(413, "Audio file too large")
                    sink.write(chunk)
            if size < 1024:
                raise HTTPException(400, "Audio file is empty")
            output = await asyncio.to_thread(convert, root, input_file)
            return FileResponse(
                output, media_type="audio/mp4",
                filename="background-without-vocals.m4a",
                background=BackgroundTask(directory.cleanup),
                headers={"Cache-Control": "no-store"},
            )
        except HTTPException:
            directory.cleanup()
            raise
        except (ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
            directory.cleanup()
            raise HTTPException(422, str(exc)[:250]) from exc
        except Exception:
            directory.cleanup()
            raise HTTPException(500, "Audio separation failed")
