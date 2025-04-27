Você deve criar 6 subdominios do tipo 'A' na Cloudflare *Status do Proxy deve esta desligado

portainer
www.portainer

traefik
www.traefik

edge
www.edge

Copie e cole no Terminal da sua VPS:
sudo apt update && sudo apt install -y git && git clone https://github.com/helenosouza/portainer.git && cd portainer && sudo chmod +x install.sh && ./install.sh

Abra o terminal e rode os seguintes comandos:

cd Portainer
docker compose down --remove-orphans
docker compose pull portainer
docker compose up -d