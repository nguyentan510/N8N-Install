#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền root."
  exit 1
fi

# Kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain | head -n1)

    if [ -z "$domain_ip" ]; then
        echo "Không thể phân giải domain $domain"
        return 1
    fi

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain đã trỏ đúng
    else
        return 1  # Domain chưa trỏ đúng
    fi
}

# Yêu cầu nhập domain
read -p "Nhập domain hoặc subdomain của bạn (ví dụ: n8n.example.com): " DOMAIN

# Kiểm tra domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN đã trỏ đúng tới server. Tiến hành cài đặt..."
else
    SERVER_IP=$(curl -s https://api.ipify.org)
    echo "Domain $DOMAIN chưa trỏ đúng tới server."
    echo "Hãy cập nhật bản ghi DNS để trỏ $DOMAIN tới IP $SERVER_IP"
    echo "Sau đó, chạy lại script này."
    exit 1
fi

# Cập nhật hệ thống
echo "Cập nhật danh sách gói và nâng cấp hệ thống..."
apt update && apt upgrade -y

# Cài đặt các gói phụ thuộc cần thiết
echo "Cài đặt các gói phụ thuộc..."
apt install -y apt-transport-https ca-certificates curl software-properties-common dnsutils

# Thêm GPG key chính thức của Docker
echo "Thêm GPG key chính thức của Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Thêm kho lưu trữ Docker vào danh sách sources
echo "Thêm kho lưu trữ Docker..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cập nhật lại danh sách gói
echo "Cập nhật lại danh sách gói từ kho lưu trữ Docker..."
apt update

# Cài đặt Docker và Docker Compose plugin
echo "Cài đặt Docker và Docker Compose plugin..."
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Khởi động Docker và bật chế độ tự khởi động cùng hệ thống
echo "Khởi động Docker và bật tự khởi động..."
systemctl start docker
systemctl enable docker

# Kiểm tra Docker và Docker Compose
echo "Kiểm tra phiên bản Docker và Docker Compose..."
DOCKER_VERSION=$(docker --version)
DOCKER_COMPOSE_VERSION=$(docker compose version)

if [[ $DOCKER_VERSION && $DOCKER_COMPOSE_VERSION ]]; then
  echo "Docker và Docker Compose đã được cài đặt thành công!"
  echo "Phiên bản Docker: $DOCKER_VERSION"
  echo "Phiên bản Docker Compose: $DOCKER_COMPOSE_VERSION"
else
  echo "Cài đặt không thành công. Vui lòng kiểm tra lại."
  exit 1
fi

# Biến môi trường và thư mục lưu trữ mặc định
POSTGRES_USER="root"
POSTGRES_PASSWORD="n8n-password"
POSTGRES_DB="n8n_maindb"
N8N_ENCRYPTION_KEY="super-secret-key"
N8N_USER_MANAGEMENT_JWT_SECRET="even-more-secret"
REDIS_PASSWORD="redis-secure-password"
N8N_DIR="/home/n8n"  # Thư mục lưu trữ dữ liệu N8N

# Tạo thư mục lưu trữ N8N nếu chưa tồn tại
echo "Tạo thư mục lưu trữ dữ liệu N8N tại $N8N_DIR..."
mkdir -p $N8N_DIR
mkdir -p $N8N_DIR/.n8n

# Tạo file docker-compose.yml
echo "Tạo file docker-compose.yml tại $N8N_DIR..."
cat << EOF > $N8N_DIR/docker-compose.yml
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      # Cấu hình cơ bản
      - N8N_HOST=${DOMAIN}
      - N8N_PROTOCOL=https
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
      - WEBHOOK_TUNNEL_URL=https://${DOMAIN}
      - WEBHOOK_URL=https://${DOMAIN}
      - N8N_EXTERNAL_URL=https://${DOMAIN}

      # Cấu hình cơ sở dữ liệu PostgreSQL
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      
      # Cấu hình Redis cho Queue Mode và Cache
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - QUEUE_BULL_REDIS_DB=0
      - EXECUTIONS_MODE=queue
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      
      # Tự động dọn dẹp dữ liệu cũ
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=50000
      
      # Thư viện ngoài cho hàm custom
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,nodemailer

      # Các cấu hình bổ sung
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - NODE_ENV=production
      
      # Cấu hình Worker
      - N8N_PAYLOAD_SIZE_MAX=16
      - EXECUTIONS_TIMEOUT=300
      - EXECUTIONS_TIMEOUT_MAX=3600

    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - $N8N_DIR/.n8n:/home/node/.n8n
    networks:
      - n8n-network

  n8n-worker:
    image: n8nio/n8n
    restart: always
    command: worker
    environment:
      # Cấu hình cơ bản
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}

      # Cấu hình cơ sở dữ liệu PostgreSQL
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      
      # Cấu hình Redis
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - QUEUE_BULL_REDIS_DB=0
      - EXECUTIONS_MODE=queue
      
      # Thư viện ngoài cho hàm custom
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,nodemailer

      # Các cấu hình bổ sung
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - NODE_ENV=production
      
      # Cấu hình Worker
      - N8N_PAYLOAD_SIZE_MAX=16
      - EXECUTIONS_TIMEOUT=300
      - EXECUTIONS_TIMEOUT_MAX=3600

    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      n8n:
        condition: service_started
    volumes:
      - $N8N_DIR/.n8n:/home/node/.n8n
    networks:
      - n8n-network

  postgres:
    image: postgres:16-alpine
    restart: always
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C --lc-ctype=C
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-network

  redis:
    image: redis:7-alpine
    restart: always
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes --appendfsync everysec
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-network

  caddy:
    image: caddy:2-alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # HTTP/3 support
    volumes:
      - $N8N_DIR/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n
    networks:
      - n8n-network

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  caddy_data:
    driver: local
  caddy_config:
    driver: local

networks:
  n8n-network:
    driver: bridge
EOF

# Tạo file Caddyfile
echo "Tạo file Caddyfile tại $N8N_DIR..."
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    encode gzip
    
    # Security headers
    header {
        # Enable HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        # Prevent clickjacking
        X-Frame-Options "SAMEORIGIN"
        # Prevent MIME sniffing
        X-Content-Type-Options "nosniff"
        # Enable XSS protection
        X-XSS-Protection "1; mode=block"
        # Remove server header
        -Server
    }
    
    # Logging
    log {
        output file /var/log/caddy/access.log
        format json
    }
}
EOF

# Đặt quyền cho thư mục N8N
echo "Đặt quyền cho thư mục $N8N_DIR..."
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động Docker Compose
echo "Khởi động Docker Compose..."
cd $N8N_DIR
docker compose up -d

# Chờ các service khởi động
echo "Đang chờ các service khởi động..."
sleep 20

# Kiểm tra trạng thái các container
echo "Kiểm tra trạng thái các container..."
docker compose ps

# Kết thúc
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ CÀI ĐẶT HOÀN TẤT!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📋 THÔNG TIN HỆ THỐNG:"
echo "────────────────────────────────────────────────────────────────"
echo "🌐 URL truy cập N8N:      https://${DOMAIN}"
echo "📂 Thư mục dữ liệu:       $N8N_DIR"
echo ""
echo "🗄️  THÔNG TIN POSTGRESQL:"
echo "────────────────────────────────────────────────────────────────"
echo "   Database:              ${POSTGRES_DB}"
echo "   User:                  ${POSTGRES_USER}"
echo "   Password:              ${POSTGRES_PASSWORD}"
echo "   Host (internal):       postgres:5432"
echo "   Host (external):       localhost:5432"
echo ""
echo "🔴 THÔNG TIN REDIS:"
echo "────────────────────────────────────────────────────────────────"
echo "   Password:              ${REDIS_PASSWORD}"
echo "   Host (internal):       redis:6379"
echo "   Host (external):       localhost:6379"
echo "   Database:              0"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "📝 HƯỚNG DẪN SỬ DỤNG:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "1️⃣  Khởi động lại hệ thống:"
echo "   cd $N8N_DIR && docker compose restart"
echo ""
echo "2️⃣  Dừng hệ thống:"
echo "   cd $N8N_DIR && docker compose stop"
echo ""
echo "3️⃣  Xem logs N8N:"
echo "   cd $N8N_DIR && docker compose logs -f n8n"
echo ""
echo "4️⃣  Xem logs Worker:"
echo "   cd $N8N_DIR && docker compose logs -f n8n-worker"
echo ""
echo "5️⃣  Xem logs Redis:"
echo "   cd $N8N_DIR && docker compose logs -f redis"
echo ""
echo "6️⃣  Kết nối Redis CLI:"
echo "   docker exec -it \$(docker ps -qf 'name=redis') redis-cli -a ${REDIS_PASSWORD}"
echo ""
echo "7️⃣  Kết nối PostgreSQL:"
echo "   docker exec -it \$(docker ps -qf 'name=postgres') psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
echo ""
echo "8️⃣  Backup PostgreSQL:"
echo "   docker exec \$(docker ps -qf 'name=postgres') pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} > backup_\$(date +%Y%m%d_%H%M%S).sql"
echo ""
echo "9️⃣  Backup Redis:"
echo "   docker exec \$(docker ps -qf 'name=redis') redis-cli -a ${REDIS_PASSWORD} SAVE"
echo "   docker cp \$(docker ps -qf 'name=redis'):/data/dump.rdb redis_backup_\$(date +%Y%m%d_%H%M%S).rdb"
echo ""
echo "🔟 Kiểm tra trạng thái containers:"
echo "   cd $N8N_DIR && docker compose ps"
echo ""
echo "1️⃣1️⃣  Xem resource usage:"
echo "   docker stats"
echo ""
echo "1️⃣2️⃣  Scale Worker (tăng số lượng worker):"
echo "   cd $N8N_DIR && docker compose up -d --scale n8n-worker=3"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🔧 KIỂM TRA HỆ THỐNG:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "✓ Kiểm tra Redis hoạt động:"
echo "  docker exec \$(docker ps -qf 'name=redis') redis-cli -a ${REDIS_PASSWORD} ping"
echo "  (Kết quả mong đợi: PONG)"
echo ""
echo "✓ Kiểm tra PostgreSQL hoạt động:"
echo "  docker exec \$(docker ps -qf 'name=postgres') pg_isready -U ${POSTGRES_USER}"
echo "  (Kết quả mong đợi: accepting connections)"
echo ""
echo "✓ Kiểm tra N8N hoạt động:"
echo "  curl -I https://${DOMAIN}"
echo "  (Kết quả mong đợi: HTTP/2 200)"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "⚠️  LƯU Ý QUAN TRỌNG:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🔐 Bảo mật:"
echo "   - Đổi tất cả passwords mặc định ngay sau khi cài đặt"
echo "   - Giữ file docker-compose.yml an toàn (chứa thông tin nhạy cảm)"
echo "   - Cân nhắc sử dụng .env file để quản lý biến môi trường"
echo ""
echo "📊 Hiệu suất:"
echo "   - Redis được cấu hình với AOF persistence (appendonly yes)"
echo "   - Worker mode giúp xử lý workflow song song"
echo "   - Có thể scale worker bằng lệnh ở mục 12"
echo ""
echo "💾 Backup:"
echo "   - Nên backup định kỳ PostgreSQL và Redis"
echo "   - Backup thư mục $N8N_DIR/.n8n"
echo "   - Kiểm tra backup thường xuyên"
echo ""
echo "🔄 Update:"
echo "   cd $N8N_DIR && docker compose pull && docker compose up -d"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "📚 TÀI LIỆU THAM KHẢO:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "   N8N Documentation:     https://docs.n8n.io"
echo "   Queue Mode:            https://docs.n8n.io/hosting/scaling/queue-mode"
echo "   Redis Documentation:   https://redis.io/docs"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Lưu thông tin này vào file để tham khảo sau:"
echo "cat > $N8N_DIR/THONG_TIN_HE_THONG.txt << 'EOFINFO'"
echo "Domain: ${DOMAIN}"
echo "PostgreSQL User: ${POSTGRES_USER}"
echo "PostgreSQL Password: ${POSTGRES_PASSWORD}"
echo "PostgreSQL Database: ${POSTGRES_DB}"
echo "Redis Password: ${REDIS_PASSWORD}"
echo "N8N Encryption Key: ${N8N_ENCRYPTION_KEY}"
echo "JWT Secret: ${N8N_USER_MANAGEMENT_JWT_SECRET}"
echo "EOFINFO"
echo ""
echo "Truy cập https://${DOMAIN} để bắt đầu sử dụng N8N!"
echo ""
echo "════════════════════════════════════════════════════════════════"
