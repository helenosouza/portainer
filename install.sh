#!/bin/bash
set -euo pipefail

# Tratar erros e mostrar linha
trap 'echo -e "\e[31m❌ Erro na linha $LINENO\e[0m"; exit 1' ERR

# Cores
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[34m'
NC='\e[0m'

# Verifica requisitos do sistema
check_system_requirements() {
    echo -e "${BLUE}Verificando requisitos do sistema...${NC}"
    local free_space
    free_space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$free_space" -lt 10 ]; then
        echo -e "${RED}❌ Espaço em disco insuficiente (<10 GB)${NC}"
        exit 1
    fi
    local total_mem
    total_mem=$(free -g | awk 'NR==2 {print $2}')
    if [ "$total_mem" -lt 2 ]; then
        echo -e "${RED}❌ Memória RAM insuficiente (<2 GB)${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Requisitos atendidos!${NC}"
}

# Exibe logo animado
show_animated_logo() {
    clear
    echo -e "${GREEN}"
    echo "  _____        _____ _  __  _________     _______  ______ ____   ____ _______ "
    echo " |  __ \ /\   / ____| |/ / |__   __\ \   / /  __ \|  ____|  _ \ / __ \__   __|"
    echo " | |__) /  \ | |    | ' /     | |   \ \_/ /| |__) | |__  | |_) | |  | | | |   "
    echo " |  ___/ /\ \| |    |  <      | |    \   / |  ___/|  __| |  _ <| |  | | | |   "
    echo " | |  / ____ \ |____| . \     | |     | |  | |    | |____| |_) | |__| | | |   "
    echo " |_| /_/    \_\_____|_|\_\    |_|     |_|  |_|    |______|____/ \____/  |_|   "
    echo -e "${NC}"
    sleep 1
}

# Exibe banner de entrada
show_banner() {
    echo -e "${GREEN}=============================================================================="
    echo -e "=                                                                            ="
    echo -e "=                 ${YELLOW}Preencha as informações solicitadas abaixo${GREEN}                 ="
    echo -e "=                                                                            ="
    echo -e "==============================================================================${NC}"
}

# Exibe progresso de passos
show_step() {
    local current=$1 total=5 percent completed
    percent=$(( current * 100 / total ))
    completed=$(( percent / 2 ))
    echo -ne "${GREEN}Passo ${YELLOW}$current/$total ${GREEN}["
    for ((i=0; i<50; i++)); do
        if [ $i -lt $completed ]; then echo -n "="; else echo -n " "; fi
    done
    echo -e "] ${percent}%${NC}"
}

### Início do script ###
clear
show_animated_logo
show_banner
echo ""

# 1) Email
show_step 1
read -p "📧 Endereço de e-mail: " email
echo ""

# 2) Domínio Traefik
show_step 2
read -p "🌐 Domínio do Traefik (ex: traefik.seudominio.com): " traefik
echo ""

# 3) Senha Traefik
show_step 3
read -s -p "🔑 Senha do Traefik (usuário:senha para basicauth): " senha
echo -e "\n"

# 4) Domínio Portainer
show_step 4
read -p "🌐 Domínio do Portainer (ex: portainer.seudominio.com): " portainer
echo ""

# 5) Domínio Edge (opcional)
show_step 5
read -p "🌐 Domínio do Edge (ex: edge.seudominio.com): " edge
echo ""

# Confirmação dos dados
clear
echo -e "${BLUE}📋 Resumo das Informações${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "📧 E-mail Traefik: ${YELLOW}$email${NC}"
echo -e "🌐 Traefik:       ${YELLOW}$traefik${NC}"
echo -e "🔑 BasicAuth:     ${YELLOW}********${NC}"
echo -e "🌐 Portainer:     ${YELLOW}$portainer${NC}"
echo -e "🌐 Edge:          ${YELLOW}$edge${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
read -p "As informações estão corretas? (y/n): " confirma
if [[ "$confirma" != "y" ]]; then
    echo -e "${RED}❌ Cancelado pelo usuário.${NC}"
    exit 0
fi

# 1) Requisitos
clear
check_system_requirements

# 2) Atualizar sistema
echo -e "${BLUE}📦 Atualizando sistema e instalando dependências...${NC}"
sudo apt update -y
sudo apt upgrade -y
echo -e "${GREEN}✅ Sistema atualizado!${NC}"

# 3) Instalar Docker
echo -e "${BLUE}🐳 Instalando Docker...${NC}"
sudo apt install -y curl
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
echo -e "${GREEN}✅ Docker instalado!${NC}"
sleep 2
clear

# 4) Gerar docker-compose.yml corrigido
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: always
    command:
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --api.insecure=true
      - --api.dashboard=true
      - --providers.docker=true
      - --log.level=ERROR
      - --certificatesresolvers.leresolver.acme.httpchallenge=true
      - --certificatesresolvers.leresolver.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.leresolver.acme.email=$email
      - --certificatesresolvers.leresolver.acme.storage=/acme.json
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json
    labels:
      # HTTP → HTTPS
      - "traefik.http.routers.http-catchall.rule=HostRegexp(\`{host:.+}\`)"
      - "traefik.http.routers.http-catchall.entrypoints=web"
      - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      # Dashboard Traefik
      - "traefik.http.routers.traefik.rule=Host(\`${traefik}\`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.tls.certresolver=leresolver"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=$senha"

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(\`${portainer}\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
      - "traefik.http.routers.portainer.tls.certresolver=leresolver"

  # Descomente e ajuste se tiver serviço 'edge'
  # edge:
  #   image: SUA_IMAGEM_EDGE:latest
  #   container_name: edge
  #   restart: always
  #   expose:
  #     - "8000"
  #   labels:
  #     - "traefik.enable=true"
  #     - "traefik.http.routers.edge.rule=Host(\`${edge}\`)"
  #     - "traefik.http.routers.edge.entrypoints=websecure"
  #     - "traefik.http.services.edge.loadbalancer.server.port=8000"
  #     - "traefik.http.routers.edge.tls.certresolver=leresolver"

volumes:
  portainer_data:
EOF

# 5) Preparar ACME storage
echo -e "${BLUE}📝 Preparando acme.json...${NC}"
rm -f acme.json
touch acme.json
chmod 600 acme.json

# 6) Subir containers
echo -e "${BLUE}🚀 Subindo containers...${NC}"
docker compose down
docker compose up -d

# Final
clear
show_animated_logo
echo -e "${GREEN}🎉 Instalação e configuração concluídas com sucesso!${NC}"
echo -e "${BLUE}👉 Acesse agora:${NC}"
echo -e "   🔗 Traefik Dashboard: https://$traefik"
echo -e "   🔗 Portainer:         https://$portainer"
echo -e "${GREEN}💡 Aguarde alguns minutos para o Let's Encrypt gerar seus certificados SSL${NC}"
