# ViePN Social Video Resolver (tùy chọn)

Dịch vụ riêng dành cho **video công khai do bạn sở hữu hoặc có quyền tải lại**.
Một URL TikTok/Facebook Reels là trang HTML, không phải tệp MP4: ứng dụng
không thể bảo đảm tải từ URL trang nếu không có trình nhận diện video.

Dịch vụ FastAPI này sử dụng yt-dlp (phần mềm nguồn mở) và ffmpeg, **không có
cookie, login, quyền truy cập vào bài riêng tư, vượt DRM hoặc gỡ watermark**.
Dịch vụ không lưu video vĩnh viễn: sau khi iPhone nhận xong tệp, thư mục tạm
được xóa. Link có thể thất bại khi TikTok/Meta đổi nền tảng, giới hạn truy cập
hoặc tác giả tắt quyền tải. Không bảo đảm mọi link đều tải được.

## Chạy bằng Docker

Từ thư mục này:

    docker build -t viepn-video-resolver .
    docker run --rm --name viepn-resolver -p 127.0.0.1:8080:8080 \
      -e VIEPN_DOWNLOAD_TOKEN="THAY_BANG_CHUOI_BI_MAT_IT_NHAT_20_KY_TU" \
      viepn-video-resolver

Đặt reverse proxy **HTTPS** (ví dụ Nginx/Caddy) phía trước, bật bảo vệ
rate limit và giới hạn body/upload. **Không** đưa server trực tiếp lên Internet
qua HTTP; không commit token vào GitHub. Máy chủ cần đủ dung lượng tạm để chứa
video và bản chuyển mã; giới hạn 15 phút, 250 MB, tối đa 2 lượt đồng thời.

Thiết lập trong iPhone ViePN Smart Video → **Kho video** → Máy chủ tải:
`https://ten-mien-cua-ban.com` và khóa bí mật tương ứng.

## API

- GET /healthz trả trạng thái
- POST /v1/download, header X-API-Key: token, JSON body:

    {"url":"https://www.tiktok.com/@author/video/123456","has_permission":true}

Trả trực tiếp body video/mp4 khi thành công. Không tạo URL CDN công khai
dùng chung. iOS tải vào file tạm của URLSession rồi xác minh AVAsset, giới hạn
kích thước và lưu vào kho riêng.

**Lưu ý:** yt-dlp là phần mềm bên thứ ba độc lập với TikTok và Meta;
khả năng hoạt động thay đổi. Nếu tác giả không cho phép tải, hãy dùng
tính năng Save video chính thức khi khả dụng hoặc xin phép trước. Không
được tải lại video của người khác để tái đăng trái phép.

## Tiêu chuẩn vận hành

Mã này là bản triển khai tham chiếu; chưa có hệ thống quota người dùng,
giám sát, cache hoặc triển khai VPS/cloud tự động. Dịch vụ phải được chạy
trên máy chủ của bạn, nếu chưa chạy app chỉ hỗ trợ tải link MP4 trực tiếp.
