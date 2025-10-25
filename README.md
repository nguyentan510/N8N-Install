
# n8n — Hướng dẫn cài đặt nhanh

1) Chuẩn bị
   - Ubuntu server (hoặc Debian tương tự), quyền root / sudo
   - Domain/subdomain đã trỏ A record về IP server
   - Mở cổng 80 và 443

2) Tải script và chạy (1 lệnh)

```bash
curl -sSL https://raw.githubusercontent.com/nguyentan510/N8N-Install/refs/heads/main/n8n-install.sh > install_n8n.sh && chmod +x install_n8n.sh && sudo ./install_n8n.sh
```

3) Hoặc chạy script cục bộ

```bash
sudo bash n8n-install.sh
```

4) Khi script hỏi
   - Nhập domain (ví dụ: n8n.example.com)
   - Script kiểm tra DNS; nếu chưa đúng, cập nhật A record rồi chạy lại

5) Kiểm tra nhanh sau cài (1–2 phút chờ dịch vụ khởi động)
   - Liệt kê container: cd /home/n8n && docker compose ps
   - Kiểm tra web: curl -I https://n8n.example.com  (mong đợi HTTP/2 200)
   - Xem logs n8n: cd /home/n8n && docker compose logs -f n8n

6) Phải làm ngay (bảo mật)
   - Thay các secret mặc định trong script trước khi chạy hoặc trong docker-compose.yml sau khi tạo:
     - POSTGRES_PASSWORD, REDIS_PASSWORD, N8N_ENCRYPTION_KEY, N8N_USER_MANAGEMENT_JWT_SECRET

7) Lệnh thường dùng
   - Restart: cd /home/n8n && docker compose restart
   - Stop: cd /home/n8n && docker compose stop
   - Redis CLI: docker exec -it $(docker ps -qf 'name=redis') redis-cli -a <REDIS_PASSWORD>
   - Postgres: docker exec -it $(docker ps -qf 'name=postgres') psql -U <POSTGRES_USER> -d <POSTGRES_DB>

8) Vị trí tệp
   - Script: n8n-install.sh (cùng thư mục với README)
   - Thư mục dữ liệu mặc định: /home/n8n

Ghi chú ngắn: nếu không truy cập được ngay sau cài, đợi 1–2 phút và kiểm tra DNS + cổng; xem logs để biết lỗi cụ thể.
