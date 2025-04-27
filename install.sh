#!/bin/bash

set -e

# Cores
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[34m'
NC='\e[0m'

# Função para verificar requisitos do sistema
check_system_requirements() {
    echo -e "${BLUE}Verificando requisitos do sistema...${NC}"

    local free_space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$free_space" -lt 10 ]; then
        echo -e "${RED}❌ Erro: Espaço em disco insuficiente. Mínimo requerido: 10GB${NC}"
        return 1
    fi

    local total_mem=$(free -g | awk 'NR==2 {print $2}')
    if [ $total_mem -lt 2 ]; then
        echo -e "${RED}❌ Erro: Memória RAM insuficiente. Mínimo requerido: 2GB${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Requisitos do sistema atendidos${NC}"
    return 0
}

show_animated_logo() {
    clear
    echo -e "${GREEN}"
    echo -e "  _____        _____ _  __  _________     _______  ______ ____   ____ _______ "
    echo -e " |  __ \\ /\\   / ____| |/ / |__   __\\ \\   / /  __ \\|  ____|  _ \\ / __ \\__   __|"
    echo -e " | |__) /  \\ | |    | ' /     | |   \\ \\_/ /| |__) | |__  | |_) | |  | | | |   "
    echo -e " |  ___/ /\\ \\| |    |  <      | |    \\   / |  ___/|  __| |  _ <| |  | | | |   "
    echo -e " | |  / ____ \\ |____| . \\     | |     | |  | |    | |____| |_) | |__| | | |   "
    echo -e " |_| /_/    \\_\\_____|_|\\_\\    |_|     |_|  |_|    |______|____/ \\____/  |_|   "
    echo -e "${NC}"
    sleep 1
}

show_banner() {
    echo -e "${GREEN}=============================================================================="
    echo -e "=                                                                            ="
    echo -e "=           ${YELLOW}Preencha as informações solicitadas abaixo${GREEN}                      ="
    echo -e "=                                                                            ="
    echo -e "==============================================================================${NC}"
}

show_step() {
    local current=$1
    local total=5
    local percent=$((current * 100 / total))
    local completed=$((percent / 2))
    echo -ne "${GREEN}Passo ${YELLOW}$current/$total ${GREEN}["
    for ((i=0; i<50; i++)); do
        if [ $i -lt $completed ]; then
            echo -ne "="
        else
            echo -ne " "
        fi
    done
    echo -e "] ${percent}%${NC}"
}

# Banner inicial
clear
show_animated_logo
show_banner
echo ""

# Coleta de dados
show_step 1
read -p "📧 Endereço de e-mail: " email
echo ""
show_step 2
read -p "🌐 Dominio do Traefik (ex: traefik.seudominio.com): " traefik
echo ""
show_step 3
read -s -p "🔑 Senha do Traefik: " senha
echo ""
echo ""
show_step 4
read -p "🌐 Dominio do Portainer (ex: portainer.seudominio.com): " portainer
echo ""
show_step 5
read -p "🌐 Dominio do Edge (ex: edge.seudominio.com): " edge
echo ""

clear
echo -e "${BLUE}📋 Resumo das Informações${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "📧 Seu E-mail: ${YELLOW}$email${NC}"
echo -e "🌐 Dominio do Traefik: ${YELLOW}$traefik${NC}"
echo -e "🔑 Senha do Traefik: ${YELLOW}********${NC}"
echo -e "🌐 Dominio do Portainer: ${YELLOW}$portainer${NC}"
echo -e "🌐 Dominio do Edge: ${YELLOW}$edge${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

read -p "As informações estão certas? (y/n): " confirma1
if [ "$confirma1" != "y" ]; then
    echo -e "${RED}❌ Instalação cancelada. Por favor, inicie novamente.${NC}"
    exit 0
fi

clear

check_system_requirements || exit 1

echo -e "${BLUE}🚀 Iniciando instalação...${NC}"

#########################################################
# INSTALANDO DEPENDÊNCIAS
#########################################################

echo -e "${YELLOW}📦 Atualizando sistema e instalando dependências...${NC}"
sudo apt update -y && sudo apt upgrade -y

sudo apt install -y curl docker.io docker-compose

sudo systemctl enable docker || true
sudo systemctl start docker || true

mkdir -p ~/Portainer
cd ~/Portainer

echo -e "${GREEN}✅ Dependências instaladas com sucesso${NC}"
sleep 1

#########################################################
# GERA SENHA EM FORMATO Bcrypt para Traefik (recomendado)
#########################################################

echo -e "${YELLOW}🔒 Gerando hash da senha para autenticação básica do Traefik...${NC}"
htpasswd_instaled=false
if ! command -v htpasswd &> /dev/null; then
    sudo apt install -y apache2-utils
fi
senha_bcrypt=$(htpasswd -nbB admin "$senha" | cut -d: -f2)
unset senha

#########################################################
# CRIANDO DOCKER-COMPOSE.YML
#########################################################
cat > docker-compose.yml <<EOL
services:
  traefik:
    container_name: traefik
    image: "traefik:latest"
    restart: always
    command:
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --api.insecure=true
      - --api.dashboard=true
      - --providers.docker
      - --log.level=ERROR
      - --certificatesresolvers.leresolver.acme.httpchallenge=true
      - --certificatesresolvers.leresolver.acme.email=$email
      - --certificatesresolvers.leresolver.acme.storage=./acme.json
      - --certificatesresolvers.leresolver.acme.httpchallenge.entrypoint=web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./acme.json:/acme.json"
    labels:
      - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
      - "traefik.http.routers.http-catchall.entrypoints=web"
      - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      - "traefik.http.routers.traefik-dashboard.rule=Host(\`$traefik\`)"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=leresolver"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=admin:$senha_bcrypt"
      - "traefik.http.routers.traefik-dashboard.middlewares=traefik-auth"
  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(\`$portainer\`)"
      - "traefik.http.routers.frontend.entrypoints=websecure"
      - "traefik.http.services.frontend.loadbalancer.server.port=9000"
      - "traefik.http.routers.frontend.service