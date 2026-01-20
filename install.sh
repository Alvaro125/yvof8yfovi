#!/bin/bash

# Script de instalação completa do ambiente
# Tarsel Redes - Ambiente de produção
# Autor: Setup automático
# Data: $(date +%Y-%m-%d)

set -e  # Parar execução em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    log_error "Por favor, execute como root (use sudo)"
    exit 1
fi

log_info "Iniciando instalação do ambiente..."

# ============================================
# 1. INSTALAR DEPENDÊNCIAS BASE
# ============================================
log_info "Instalando dependências base..."
apt clean
apt update
apt install -y ca-certificates curl gnupg git wget tar

# ============================================
# 2. INSTALAR DOCKER
# ============================================
log_info "Instalando Docker..."

# Criar diretório para keyrings
install -m 0755 -d /etc/apt/keyrings

# Adicionar chave GPG do Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Adicionar repositório do Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

# Instalar Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Verificar instalação
docker --version
docker compose version

log_info "Docker instalado com sucesso!"

# ============================================
# 3. CRIAR DIRETÓRIO DE TRABALHO
# ============================================
log_info "Criando estrutura de diretórios..."
WORK_DIR="/home/solunet"
mkdir -p $WORK_DIR
mkdir -p $WORK_DIR/filters
cd $WORK_DIR

# ============================================
# 4. CRIAR ARQUIVO .env
# ============================================
log_info "Criando arquivo de configuração .env..."
cat > .env << 'EOF'
DIR_IP=38.191.43.78
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_USER=admindb
DATABASE_PASSWORD=admin
DATABASE_NAME=portalusers
SECRET_KEY=6A537424934E0AE36928E8128EC9F702
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
FASTAPI_PORT=5002
DJANGO_PORT=8000
CLICKHOUSE_PORT=9000
GO_PORT=1323
GOBGP_PORT=50051
FRONT_PORT=3000
LANGUAGE=en
COLLECTIONS_JSON=/home/solunet/filters/collections.json
HOST_FILTER_DIR=/home/solunet/filters/
REDIS_URL="redis://redis:6379/1"
BMP_PORT=10179
DEV=true
SERVER_IP=38.191.43.78
EOF

log_info "Arquivo .env criado!"

# ============================================
# 5. CRIAR ARQUIVO init.sql
# ============================================
log_info "Criando script de inicialização do banco de dados..."
cat > init.sql << 'EOSQL'
CREATE SCHEMA IF NOT EXISTS public AUTHORIZATION postgres;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tabelas

CREATE TABLE IF NOT EXISTS userbase (
    name TEXT NOT NULL,
    lastname TEXT NOT NULL,
    username TEXT NOT NULL PRIMARY KEY,
    email TEXT NOT NULL,
    password TEXT NOT NULL,
    profile TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS ips (
    id BIGSERIAL PRIMARY KEY,
    id_client TEXT NOT NULL REFERENCES userbase(username) ON DELETE CASCADE,
    ip_direction TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS ddos
(
    id UUID DEFAULT uuid_generate_v4(),
    id_client TEXT NOT NULL,
    rede TEXT NULL,
    protocol TEXT NOT NULL,
    unit TEXT NOT NULL,
    port TEXT,
    avg TEXT NOT NULL,
    max TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (id),
    action1 TEXT,
    action2 TEXT
);

CREATE TABLE IF NOT EXISTS redes
(
    id_client TEXT NOT NULL,
    rede_name TEXT NULL,
    rede_ip TEXT NULL,
    PRIMARY KEY (id_client, rede_name, rede_ip)
);

CREATE TABLE IF NOT EXISTS interfaces
(
    interface_id SERIAL PRIMARY KEY,
    router_name VARCHAR(255) NOT NULL,
    interface_name VARCHAR(255) NOT NULL,
    interface_type VARCHAR(255) NOT NULL,
    bandwith_capacity DECIMAL(10, 2) NOT NULL,
    current_use DECIMAL(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS capacity_planning
(
    planning_id SERIAL PRIMARY KEY,
    plan_name VARCHAR(255) NOT NULL,
    description TEXT,
    interface_ids INT[],
    plan_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    medium_threshold_runout DECIMAL(10, 2) NOT NULL,
    high_threshold_runout DECIMAL(10, 2) NOT NULL,
    medium_threshold_utilization DECIMAL(10, 2) NOT NULL,
    high_threshold_utilization DECIMAL(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS states (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS devices (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    state_id INTEGER,
    state_name VARCHAR(255) NOT NULL,
    fps_raw INTEGER NOT NULL,
    fps_sampled INTEGER NOT NULL,
    site VARCHAR(255) NOT NULL,
    ip_address INET NOT NULL,
    plan_id INTEGER,
    plan_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS preferences (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS user_preferences (
    user_id TEXT PRIMARY KEY REFERENCES userbase(username) ON DELETE CASCADE,
    preference_id INT[]
);

CREATE TABLE IF NOT EXISTS event_log (
    id SERIAL PRIMARY KEY,
    user_id TEXT,
    action_type VARCHAR(50) NOT NULL,
    action_description TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address INET NOT NULL,
    user_agent TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS flowspec_rate_limit (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    source_ip TEXT NOT NULL,
    destination_ip TEXT NOT NULL,
    protocol TEXT NOT NULL,
    source_port TEXT,
    destination_port TEXT,
    rate_limit_mbps NUMERIC(10, 3),
    description TEXT,
    status BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS support (
    id_client TEXT NOT NULL REFERENCES userbase(username) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    type TEXT NOT NULL,
    date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    state TEXT NOT NULL DEFAULT 'OPEN'
);

-- Triggers

CREATE OR REPLACE FUNCTION replace_ids_with_names() RETURNS TRIGGER AS $$
BEGIN
    SELECT name INTO NEW.state_name FROM states WHERE id = NEW.state_id;
    SELECT name INTO NEW.plan_name FROM plans WHERE id = NEW.plan_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'before_insert_devices') THEN
        CREATE TRIGGER before_insert_devices
        BEFORE INSERT ON devices
        FOR EACH ROW
        EXECUTE FUNCTION replace_ids_with_names();
    END IF;
END $$;
EOSQL

log_info "Script init.sql criado!"

# ============================================
# 6. CRIAR docker-compose.yml
# ============================================
log_info "Criando docker-compose.yml..."
cat > docker-compose.yml << 'EODC'
services:
    django:
        image: tarselredes/tarsel_backend:latest
        build:
            context: .
            dockerfile: Dockerfile
        env_file:
            - .env
        ports:
            - "${DJANGO_PORT}:${DJANGO_PORT}"
        networks:
            - docker_default
        entrypoint: ["python", "/app/manage.py", "runserver", "0.0.0.0:${DJANGO_PORT}"]
        healthcheck:
            test: ["CMD", "curl", "-f", "http://${DIR_IP}:${DJANGO_PORT}"]
            interval: 30s
            timeout: 10s
            retries: 5
    fastapi:
        image: tarselredes/tarsel_backend:latest
        env_file:
            - .env
        ports:
            - "${FASTAPI_PORT}:${FASTAPI_PORT}"
        networks:
            - docker_default
        volumes:
            - ${HOST_FILTER_DIR}:/app/json/filters/
        entrypoint: ["uvicorn", "website.fastapi_main:app", "--host", "0.0.0.0", "--port", "${FASTAPI_PORT}"]
        depends_on:
            - django
        healthcheck:
            test: ["CMD", "curl", "-f", "http://${DIR_IP}:${FASTAPI_PORT}"]
            interval: 30s
            timeout: 10s
            retries: 5
    go:
        image: tarselredes/tarsel_backend:latest
        env_file:
            - .env
        ports:
            - "${GO_PORT}:${GO_PORT}"
        networks:
            - docker_default
        command: /app/build
        depends_on:
            - django
            - fastapi
        healthcheck:
            test: ["CMD", "curl", "-f", "http://${DIR_IP}:${GO_PORT}"]
            interval: 30s
            timeout: 10s
            retries: 5
    postgres:
        image: postgres:17
        env_file:
            - .env
        environment:
            - POSTGRES_USER=${DATABASE_USER}
            - POSTGRES_PASSWORD=${DATABASE_PASSWORD}
            - POSTGRES_DB=${DATABASE_NAME}
        ports:
            - "${DATABASE_PORT}:${DATABASE_PORT}"
        volumes:
            - postgres_data:/var/lib/postgresql
            - ./init.sql:/docker-entrypoint-initdb.d/init.sql
        networks:
            - docker_default
        healthcheck:
            test: ["CMD-SHELL", "pg_isready -U ${DATABASE_USER}"]
            interval: 30s
            timeout: 10s
            retries: 5
    redis:
        image: redis:latest
        ports:
            - "6379:6379"
        networks:
            - docker_default
        healthcheck:
            test: ["CMD", "redis-cli", "ping"]
            interval: 30s
            timeout: 10s
            retries: 5
networks:
    docker_default:
        external: true
volumes:
  postgres_data:
EODC

log_info "docker-compose.yml criado!"

# ============================================
# 7. CRIAR REDE DOCKER
# ============================================
log_info "Criando rede Docker..."
docker network create docker_default 2>/dev/null || log_warn "Rede docker_default já existe"

# ============================================
# 8. INSTALAR AKVORADO
# ============================================
log_info "Instalando Akvorado..."
cd /opt
mkdir -p akvorado
cd akvorado
curl -sL https://github.com/akvorado/akvorado/releases/latest/download/docker-compose-quickstart.tar.gz | tar zxvf -

log_info "Iniciando Akvorado..."
docker compose up -d --wait

# ============================================
# 9. INSTALAR NVM E NODE.js
# ============================================
log_info "Instalando NVM e Node.js..."
cd $WORK_DIR

# Instalar NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# Carregar NVM no shell atual
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Instalar Node.js 18.19.0
nvm install 18.19.0
nvm use 18.19.0

# Instalar PM2 globalmente
npm install -g pm2

log_info "NVM e Node.js instalados!"

# ============================================
# 10. BAIXAR E CONFIGURAR TARSELVISUALIZER
# ============================================
log_info "Baixando TarselVisualizer..."
cd $WORK_DIR
wget https://raw.githubusercontent.com/Alvaro125/yvof8yfovi/refs/heads/main/TarselVisualizer-fix.tar.gz
tar -xzf TarselVisualizer-fix.tar.gz
cd TarselVisualizer-fix

log_info "Instalando dependências do TarselVisualizer..."
npm ci

log_info "Compilando projeto..."
npm run build

log_info "Parando processos PM2 anteriores..."
pm2 kill

log_info "Iniciando TarselVisualizer com PM2..."
pm2 start .output/server/index.mjs --name "tarsel-visualizer"

# Salvar configuração do PM2
pm2 save
pm2 startup

# ============================================
# 11. INICIAR CONTAINERS DO BACKEND
# ============================================
log_info "Iniciando containers do backend..."
cd $WORK_DIR
docker compose --profile postgres up -d

# ============================================
# 12. VERIFICAR STATUS
# ============================================
log_info "Verificando status dos containers..."
sleep 5
docker ps

# ============================================
# FINALIZAÇÃO
# ============================================
echo ""
log_info "============================================"
log_info "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
log_info "============================================"
echo ""
log_info "Serviços instalados:"
log_info "  - Docker e Docker Compose"
log_info "  - PostgreSQL (porta 5432)"
log_info "  - Redis (porta 6379)"
log_info "  - Django (porta 8000)"
log_info "  - FastAPI (porta 5002)"
log_info "  - Go Service (porta 1323)"
log_info "  - Akvorado (/opt/akvorado)"
log_info "  - TarselVisualizer (PM2)"
echo ""
log_info "Comandos úteis:"
log_info "  - Ver containers: docker ps"
log_info "  - Ver logs: docker compose logs -f"
log_info "  - Parar tudo: docker compose down"
log_info "  - Status PM2: pm2 status"
log_info "  - Logs PM2: pm2 logs"
echo ""
log_info "Para recarregar NVM em novas sessões, execute:"
log_info "  export NVM_DIR=\"\$HOME/.nvm\""
log_info "  [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\""
echo ""
log_info "Acesse o PostgreSQL:"
log_info "  docker exec -it solunet-postgres-1 psql -U admindb -d portalusers"
echo ""