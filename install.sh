#!/bin/bash
set -euo pipefail

# Captura erros e aponta a linha
trap 'echo -e "\e[31m❌ Erro na linha $LINENO\e[0m"; exit 1' ERR

# Cores
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[34m'
NC='\e[0m'

# Função para verificar requisitos do sistema
check_system_requirements() {
    echo -e "${BLUE}Verificando requisitos do sistema...${NC}"
    
    local free_space
    free_space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$free_space" -lt 10 ]; then
        echo -e "${RED}❌ Espaço insuficiente (<10 GB)${NC}"
        exit 1
    fi
    
    local total_mem
    total_mem=$(free -g | awk 'NR==2 {print $2}')
    if [ "$total_mem" -lt 2 ]; then
        echo -e "${RED}❌ RAM insuficiente (<2 GB)${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Requisitos atendidos!${NC}"
}

# Logo animado (sem spinner de fundo, apenas pausa)
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

# Banner de entrada
show_banner() {
    echo -e "${GREEN}=============================================================================="
    echo -e "=                                                                            ="
    echo -e "=                 ${YELLOW}Preencha as informações solicitadas abaixo${GREEN}                 ="
    echo -e "=                                                                            ="
    echo -e "==============================================================================${NC}"
}

# Progressão de passos
show_step() {
    local current=$1 total=5 percent completed
    percent=$((current * 100 / total))
    completed=$((percent / 2))
    echo -ne "${GREEN}Passo ${YELLOW}$current/$total ${GREEN}["
    for ((i=0; i<50; i++)); do
        if [ $i -lt $completed ]; then echo -n "="; else echo -n " "; fi
    done
    echo -e "] ${percent}%${NC}"
}

# Início
clear
show_animated_logo
show_banner
echo ""

show_step 1
read -p "📧 Endereço de e-mail: " email
echo ""
show_step 2
read -p "🌐 Domínio do Traefik (ex: traefik.seudominio.com): " traefik
echo ""
show_step 3
read -s -p "🔑 Senha do Traefik: " senha
echo -e "\n"
show_step 4
read -p "🌐 Domínio do Portainer (ex: portainer.seudominio.com): " portainer
echo ""
show_step 5
read -p "🌐 Domínio do Edge (ex: edge.seudominio.com): " edge
echo ""

# Confirmação
clear
echo -e "${BLUE}📋 Resumo das Informações${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "📧 Seu E-mail:    ${YELLOW}$email${NC}"
echo -e "🌐 Traefik:       ${YELLOW}$traefik${NC}"
echo -e "🔑 Senha Traefik: ${YELLOW}********${NC}"
echo -e "🌐 Portainer:     ${YELLOW}$portainer${NC}"
echo -e "🌐 Edge:          ${YELLOW}$edge${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
read -p "As informações estão certas? (y/n): " confirma1

if [[ "$confirma1" == "y" ]]; then
    clear
    check_system_requirements

    echo -e "${BLUE}🚀 Iniciando instalação...${NC}"

    echo -e "${YELLOW}📦 Atualizando sistema e instalando dependências...${NC}"
    # Aqui toda saída será mostrada no terminal
    sudo apt update -y
    sudo apt upgrade -y

    echo -e "${GREEN}✅ Sistema atualizado com sucesso${NC}"

    echo -e "${YELLOW}🐳 Instalando Docker...${NC}"
    sudo apt install -y curl
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh

    echo -e "${GREEN}✅ Docker instalado com sucesso${NC}"
    sleep 2
    clear

    # Gera docker-compose.yml
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
      - "traefik.http.middlewares.traefik-auth.basicauth.users=$senha"
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
      - "traefik.http.routers.frontend.service=frontend"
      - "traefik.http.routers.frontend.tls.certresolver=leresolver"
      - "traefik.http.routers.edge.rule=Host(\`$edge\`)"
      - "traefik.http.routers.edge.entrypoints=websecure"
      - "traefik.http.services.edge.loadbalancer.server.port=8000"
      - "traefik.http.routers.edge.service=edge"
      - "traefik.http.routers.edge.tls.certresolver=leresolver"
volumes:
  portainer_data:
EOL

    echo -e "${YELLOW}📝 Preparando acme.json...${NC}"
    touch acme.json
    sudo chmod 600 acme.json

    echo -e "${YELLOW}🚀 Subindo containers...${NC}"
    sudo docker compose up -d

    clear
    show_animated_logo

    echo -e "${GREEN}🎉 Instalação concluída com sucesso!${NC}"
    echo -e "${BLUE}📝 Acesse:${NC}"
    echo -e "   🔗 Portainer: https://$portainer"
    echo -e "   🔗 Traefik:   https://$traefik"
    echo -e "${GREEN}💡 Aguarde alguns minutos para geração de SSL${NC}"
else
    echo -e "${RED}❌ Instalação cancelada. Reinicie o script para tentar novamente.${NC}"
    exit 0
fi
