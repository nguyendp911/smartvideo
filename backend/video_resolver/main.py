"""Optional self-hosted resolver for authorized public TikTok/Facebook videos.

Runs without cookies, login, private-media access, watermark removal, DRM
bypass, or persistent server-side video storage. A dedicated endpoint is
required because a social post URL is an HTML page, not a video URL.
"""
import asyncio
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

import yt_dlp
from fastapi import FastAPI, Header, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

app = FastAPI(title="ViePN Authorized Video Resolver", version="1.0.0",
              docs_url=None, redoc_url=None)
MAX_BYTES = 250 * 1024 * 1024
MAX_DURATION = 15 * 60
ALLOWED_HOSTS = {
    "tiktok.com", "www.tiktok.com", "m.tiktok.com",
    "vm.tiktok.com", "vt.tiktok.com", "facebook.com",
    "www.facebook.com", "m.facebook.com", "web.facebook.com",
    "fb.watch", "www.fb.watch", "fb.com", "www.fb.com",
}
LIMIT = asyncio.Semaphore(2)


class RequestVideo(BaseModel):
    url: str = Field(min_length=12, max_length=2048)
    has_permission: bool = False


def validate_url(value: str) -> str:
    parsed = urlsplit(value.strip())
    if (parsed.scheme != "https" or not parsed.hostname
            or parsed.username or parsed.password or parsed.port
            or parsed.hostname.lower() not in ALLOWED_HOSTS):
        raise ValueError("Chỉ chấp nhận HTTPS từ tên miền TikTok/Facebook thực.")
    if not parsed.path or parsed.path == "/":
        raise ValueError("Cần liên kết trực tiếp đến một bài video.")
    return value.strip()


def _download(url: str, folder: Path) -> Path:
    def check_duration(info, *, incomplete=False):
        duration = info.get("duration")
        if duration is not None and duration > MAX_DURATION:
            return "Video dài hơn giới hạn 15 phút."
        if info.get("is_live"):
            return "Không hỗ trợ live stream."
        return None

    opts = {
        "format": "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b",
        "outtmpl": str(folder / "%(id).80s.%(ext)s"),
        "merge_output_format": "mp4",
        "noplaylist": True,
        "nooverwrites": True,
        "restrictfilenames": True,
        "ignoreerrors": False,
        "no_warnings": True,
        "quiet": True,
        "max_filesize": MAX_BYTES,
        "match_filter": check_duration,
        "cachedir": False,
        # Never use browser cookies, stored credentials, or private sessions.
        "cookiefile": None,
    }
    with yt_dlp.YoutubeDL(opts) as dl:
        info = dl.extract_info(url, download=True)
        if not info or info.get("_type") == "playlist":
            raise ValueError("Không tìm được một video công khai hợp lệ.")

    files = [
        p for p in folder.iterdir()
        if p.is_file() and p.suffix.lower() in
        {".mp4", ".mov", ".webm", ".mkv"}
    ]
    if not files:
        raise ValueError("Không trích xuất được tệp video.")
    source = max(files, key=lambda p: p.stat().st_size)
    if source.stat().st_size > MAX_BYTES:
        raise ValueError("Video vượt quá 250 MB.")

    if source.suffix.lower() == ".mp4":
        return source

    converted = folder / "viepn-converted.mp4"
    command = [
        "ffmpeg", "-nostdin", "-v", "error", "-y",
        "-i", str(source), "-t", str(MAX_DURATION),
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
        "-pix_fmt", "yuv420p", "-c:a", "aac",
        "-movflags", "+faststart", str(converted),
    ]
    subprocess.run(command, check=True, timeout=420)
    if not converted.is_file() or converted.stat().st_size > MAX_BYTES:
        raise ValueError("Không thể chuyển video sang MP4 hoặc video quá lớn.")
    return converted


@app.get("/healthz")
def health() -> dict:
    return {"ok": True, "mode": "authorized-public-media-only"}


@app.post("/v1/download")
async def download_video(
    payload: RequestVideo,
    background_tasks: BackgroundTasks,
    x_api_key: str | None = Header(default=None),
):
    token = os.environ.get("VIEPN_DOWNLOAD_TOKEN", "")
    if len(token) < 20:
        raise HTTPException(status_code=503,
                            detail="Máy chủ chưa cấu hình khóa truy cập.")
    import secrets
    if not secrets.compare_digest(x_api_key or "", token):
        raise HTTPException(status_code=401, detail="Khóa truy cập không đúng.")
    if not payload.has_permission:
        raise HTTPException(status_code=400,
                            detail="Bạn phải có quyền tải/lưu video này.")
    try:
        url = validate_url(payload.url)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    directory = Path(tempfile.mkdtemp(prefix="viepn-public-video-"))
    try:
        # For low-traffic self-hosted environments. Use a task queue at scale.
        async with LIMIT:
            video = await asyncio.to_thread(_download, url, directory)
        background_tasks.add_task(shutil.rmtree, directory, ignore_errors=True)
        return FileResponse(
            video, media_type="video/mp4",
            filename="ViePN-Authorized-Video.mp4",
            background=background_tasks,
            headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
        )
    except Exception as exc:
        shutil.rmtree(directory, ignore_errors=True)
        # Do not expose upstream signed CDN URLs/cookies in HTTP errors.
        raise HTTPException(
            status_code=422,
            detail="Không trích xuất được video công khai được cho phép. "
                   "Link có thể hết hạn, không hỗ trợ hoặc nền tảng đã thay đổi.",
        ) from exc
