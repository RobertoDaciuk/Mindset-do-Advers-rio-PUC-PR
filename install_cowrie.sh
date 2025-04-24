#!/bin/bash
# =============================================================
# COWRIE HONEYPOT DOCKER INSTALLER - By Roberto Daciuk 
# Versão: 1.0 - Instalação Completa em Container Docker
# =============================================================

# ------------------------------
# 🎨 CONFIGURAÇÃO DE CORES (RGB)
# ------------------------------
BOLD=$(tput bold)
RESET=$(tput sgr0)
BLACK=$(tput setaf 0)
RED=$(tput setaf 196)
GREEN=$(tput setaf 46)
YELLOW=$(tput setaf 226)
BLUE=$(tput setaf 39)
MAGENTA=$(tput setaf 129)
CYAN=$(tput setaf 51)
WHITE=$(tput setaf 255)

# Cores de fundo
BG_RED=$(tput setab 196)
BG_GREEN=$(tput setab 46)
BG_BLUE=$(tput setab 27)
BG_YELLOW=$(tput setab 226)

# ------------------------------
# 🔧 VARIÁVEIS GLOBAIS
# ------------------------------
BASE_DIR="/opt/cowrie_docker"
DATA_DIR="$BASE_DIR/data"
LOG_DIR="/var/log/cowrie_docker"
INSTALL_LOG="$LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"
DEFAULT_PORT=2222
COWRIE_IMAGE="cowrie/cowrie:latest"
CONTAINER_NAME="cowrie_honeypot"
DOCKER_COMPOSE_VERSION="2.23.0"

# ------------------------------
# 📝 FUNÇÕES DE LOG E INTERFACE
# ------------------------------
init_logging() {
    sudo mkdir -p "$LOG_DIR"
    sudo chown -R $(whoami):$(whoami) "$LOG_DIR"
    exec > >(tee -a "$INSTALL_LOG") 2>&1
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    case "$level" in
        "INFO")    color="$BLUE";    prefix="ℹ" ;;
        "SUCCESS") color="$GREEN";   prefix="✓" ;;
        "WARNING") color="$YELLOW";  prefix="⚠" ;;
        "ERROR")   color="$RED";     prefix="✖" ;;
        *)         color="$WHITE";   prefix="?" ;;
    esac
    echo -e "${color}[${timestamp}] ${prefix} ${message}${RESET}"
}

print_header() {
    clear
    echo -e "${BG_BLUE}${WHITE}${BOLD}"
    echo -e "╔════════════════════════════════════════════════════════════╗"
    echo -e "║        COWRIE DOCKER INSTALLER - By Roberto Daciuk         ║"
    echo -e "╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_section() {
    local title="$1"
    echo -e "\n${CYAN}${BOLD}${title}${RESET}"
    echo -e "${MAGENTA}${BOLD}────────────────────────────────────────────────────────────────${RESET}"
}

pause() {
    echo -e "\n${YELLOW}${BOLD}Pressione Enter para continuar...${RESET}"
    read
}

# ------------------------------
# 🔍 VERIFICAÇÕES DO SISTEMA
# ------------------------------
check_system() {
    print_section "VERIFICAÇÃO INICIAL DO SISTEMA"
    
    echo -e "${BOLD}${WHITE}Verificando requisitos do sistema:${RESET}"
    
    # Verificar se é Ubuntu/Debian
    if ! grep -qEi 'ubuntu|debian' /etc/os-release; then
        log "WARNING" "Sistema não testado: $(lsb_release -ds)"
        echo -e "${YELLOW}Este script foi otimizado para Ubuntu/Debian.${RESET}"
        pause
    fi

    # Verificar se é root
    if [ "$(id -u)" -eq 0 ]; then
        log "ERROR" "Este script não deve ser executado como root"
        echo -e "${RED}Por segurança, execute como um usuário normal com sudo.${RESET}"
        exit 1
    fi

    # Verificar conexão com a internet
    echo -e "${BLUE}Testando conexão com a internet...${RESET}"
    if ! ping -c 1 google.com &> /dev/null; then
        log "ERROR" "Sem conexão com a internet"
        echo -e "${RED}Você precisa de conexão com a internet para baixar os containers.${RESET}"
        exit 1
    fi

    log "SUCCESS" "Verificações básicas concluídas"
    pause
}

# ------------------------------
# 🐳 INSTALAÇÃO DO DOCKER
# ------------------------------
install_docker() {
    print_section "INSTALAÇÃO DO DOCKER"
    
    # Verificar se o Docker já está instalado
    if command -v docker &> /dev/null; then
        log "INFO" "Docker já está instalado: $(docker --version)"
        echo -e "${GREEN}✔ Docker já está instalado${RESET}"
        return 0
    fi

    echo -e "${BOLD}${WHITE}Instalando Docker e Docker Compose:${RESET}"
    echo -e "Serão instalados os seguintes pacotes:"
    echo -e "  - docker.io (motor Docker)"
    echo -e "  - docker-compose-plugin (compose integrado)"
    echo -e "  - containerd (runtime de containers)"
    
    pause

    # Instalar dependências
    echo -e "\n${BLUE}Instalando pacotes necessários...${RESET}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release || {
        log "ERROR" "Falha ao instalar dependências"
        exit 1
    }

    # Adicionar repositório oficial do Docker
    echo -e "\n${BLUE}Configurando repositório do Docker...${RESET}"
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Instalar Docker
    echo -e "\n${BLUE}Instalando Docker Engine...${RESET}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-compose-plugin || {
        log "ERROR" "Falha ao instalar Docker"
        exit 1
    }

    # Configurar usuário atual para usar Docker sem sudo
    echo -e "\n${BLUE}Configurando permissões...${RESET}"
    sudo usermod -aG docker "$(whoami)"
    newgrp docker

    # Testar instalação
    if docker run --rm hello-world &> /dev/null; then
        log "SUCCESS" "Docker instalado com sucesso: $(docker --version)"
        echo -e "${GREEN}✔ Docker está funcionando corretamente${RESET}"
    else
        log "ERROR" "Problema na instalação do Docker"
        echo -e "${RED}✖ A instalação do Docker falhou${RESET}"
        exit 1
    fi

    pause
}

# ------------------------------
# 🔐 CONFIGURAÇÃO DE SEGURANÇA
# ------------------------------
configure_security() {
    print_section "CONFIGURAÇÃO DE SEGURANÇA"
    
    echo -e "${BOLD}${WHITE}Configuração de Portas e Firewall:${RESET}"
    
    # Perguntar sobre a porta SSH do Cowrie
    while true; do
        echo -e "\n${YELLOW}Em qual porta o Cowrie deve escutar? (Padrão: $DEFAULT_PORT)${RESET}"
        echo -e "${BLUE}Recomendação: Use uma porta acima de 1024 (ex: 2222) para evitar conflitos${RESET}"
        read -p "Porta: " COWRIE_PORT
        
        if [ -z "$COWRIE_PORT" ]; then
            COWRIE_PORT=$DEFAULT_PORT
            break
        elif [[ "$COWRIE_PORT" =~ ^[0-9]+$ ]] && [ "$COWRIE_PORT" -lt 65536 ]; then
            break
        else
            echo -e "${RED}Porta inválida! Deve ser um número entre 1 e 65535${RESET}"
        fi
    done
    
    # Configurar firewall
    echo -e "\n${YELLOW}Deseja configurar o firewall (UFW) para permitir a porta $COWRIE_PORT? [s/N]${RESET}"
    read -p "Resposta: " configure_ufw
    
    if [[ "$configure_ufw" =~ ^[Ss](im)?$ ]]; then
        echo -e "${BLUE}Configurando UFW...${RESET}"
        sudo ufw allow "$COWRIE_PORT"
        sudo ufw allow ssh  # Manter acesso SSH real
        sudo ufw --force enable
        echo -e "${GREEN}✔ Firewall configurado. Portas abertas:${RESET}"
        sudo ufw status
    else
        echo -e "${YELLOW}⚠ Firewall não foi configurado. Certifique-se de abrir a porta $COWRIE_PORT manualmente se necessário.${RESET}"
    fi
    
    # Criar estrutura de diretórios
    echo -e "\n${BLUE}Criando diretórios para persistência de dados...${RESET}"
    sudo mkdir -p "$DATA_DIR"/{etc,cowrie,log,downloads}
    sudo chown -R 1000:1000 "$DATA_DIR"
    sudo chmod -R 750 "$DATA_DIR"
    
    log "SUCCESS" "Configurações de segurança concluídas"
    pause
}

# ------------------------------
# 🐝 INSTALAÇÃO DO COWRIE
# ------------------------------
install_cowrie() {
    print_section "INSTALAÇÃO DO COWRIE EM DOCKER"
    
    echo -e "${BOLD}${WHITE}Baixando e configurando a imagem Docker do Cowrie:${RESET}"
    
    # Baixar imagem do Cowrie
    echo -e "\n${BLUE}Baixando imagem $COWRIE_IMAGE...${RESET}"
    docker pull "$COWRIE_IMAGE" || {
        log "ERROR" "Falha ao baixar imagem do Cowrie"
        exit 1
    }
    
    # Criar arquivo de configuração docker-compose.yml
    echo -e "\n${BLUE}Criando arquivo docker-compose.yml...${RESET}"
    cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: '3'
services:
  cowrie:
    image: $COWRIE_IMAGE
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
      - "$COWRIE_PORT:2222"
    volumes:
      - $DATA_DIR/etc:/cowrie/cowrie-git/etc
      - $DATA_DIR/cowrie:/cowrie/cowrie-git/var/lib/cowrie
      - $DATA_DIR/log:/cowrie/cowrie-git/var/log/cowrie
      - $DATA_DIR/downloads:/cowrie/cowrie-git/var/lib/cowrie/downloads
    environment:
      - COWRIE_JSONLOG=1
      - COWRIE_TELNET_ENABLED=0
      - COWRIE_SSH_ENABLED=1
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

    # Iniciar o container
    echo -e "\n${BLUE}Iniciando container Cowrie...${RESET}"
    cd "$BASE_DIR" && docker compose up -d || {
        log "ERROR" "Falha ao iniciar container Cowrie"
        exit 1
    }
    
    # Verificar se o container está rodando
    if docker ps -f name="$CONTAINER_NAME" | grep -q "$CONTAINER_NAME"; then
        log "SUCCESS" "Container Cowrie iniciado com sucesso"
        echo -e "${GREEN}✔ Cowrie está rodando no Docker${RESET}"
    else
        log "ERROR" "Problema ao iniciar container Cowrie"
        echo -e "${RED}✖ O container não está rodando${RESET}"
        exit 1
    fi
    
    pause
}

# ------------------------------
# 📊 PAINEL DE STATUS
# ------------------------------
show_dashboard() {
    clear
    print_header
    
    # Obter informações do container
    local container_info
    container_info=$(docker inspect "$CONTAINER_NAME" 2>/dev/null)
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')
    
    echo -e "${BOLD}${WHITE}🔧 STATUS DO COWRIE HONEYPOT:${RESET}\n"
    
    # Verificar se o container está rodando
    if docker ps -f name="$CONTAINER_NAME" | grep -q "$CONTAINER_NAME"; then
        echo -e "  ${GREEN}✓ Container $CONTAINER_NAME está em execução${RESET}"
        
        # Mostrar portas mapeadas
        local ports
        ports=$(docker port "$CONTAINER_NAME" 2>/dev/null | grep "2222/tcp" | awk '{print $3}')
        echo -e "  ${GREEN}✓ Porta do container mapeada para: $ports${RESET}"
    else
        echo -e "  ${RED}✖ Container $CONTAINER_NAME não está em execução${RESET}"
    fi
    
    # Verificar logs
    if [ -d "$DATA_DIR/log" ]; then
        local log_count
        log_count=$(find "$DATA_DIR/log" -name "cowrie.json*" | wc -l)
        echo -e "  ${GREEN}✓ Logs encontrados ($log_count arquivos de log)${RESET}"
    else
        echo -e "  ${YELLOW}⚠ Nenhum log encontrado ainda${RESET}"
    fi
    
    # Mostrar informações de rede
    echo -e "\n${BOLD}${WHITE}🌐 INFORMAÇÕES DE REDE:${RESET}"
    echo -e "  ${CYAN}▸ IP do Host:${RESET} $ip_address"
    echo -e "  ${CYAN}▸ Porta SSH do Honeypot:${RESET} $COWRIE_PORT"
    echo -e "  ${CYAN}▸ Porta Interna do Container:${RESET} 2222"
    
    # Mostrar informações de configuração
    echo -e "\n${BOLD}${WHITE}⚙️ CONFIGURAÇÃO:${RESET}"
    echo -e "  ${YELLOW}▸ Imagem Docker:${RESET} $COWRIE_IMAGE"
    echo -e "  ${YELLOW}▸ Diretório de Dados:${RESET} $DATA_DIR"
    echo -e "  ${YELLOW}▸ Arquivo de Config:${RESET} $DATA_DIR/etc/cowrie.cfg"
    
    # Mostrar comandos úteis
    echo -e "\n${BOLD}${WHITE}📊 COMANDOS ÚTEIS:${RESET}"
    echo -e "  ${BLUE}▸ Ver logs em tempo real:${RESET} docker logs -f $CONTAINER_NAME"
    echo -e "  ${BLUE}▸ Acessar shell do container:${RESET} docker exec -it $CONTAINER_NAME /bin/bash"
    echo -e "  ${BLUE}▸ Parar o container:${RESET} docker stop $CONTAINER_NAME"
    echo -e "  ${BLUE}▸ Iniciar o container:${RESET} docker start $CONTAINER_NAME"
    echo -e "  ${BLUE}▸ Reiniciar o container:${RESET} docker restart $CONTAINER_NAME"
    
    # Mostrar informações de conexão
    echo -e "\n${BOLD}${WHITE}🔍 TESTE DE CONEXÃO:${RESET}"
    echo -e "  ${MAGENTA}▸ Testar conexão SSH:${RESET} ssh root@$ip_address -p $COWRIE_PORT"
    echo -e "  ${MAGENTA}▸ Senha padrão:${RESET} qualquer senha será aceita (honeypot)"
    
    # Log detalhado
    log "INFO" "Instalação concluída - IP: $ip_address Porta: $COWRIE_PORT"
    log "INFO" "Diretório de dados: $DATA_DIR"
    log "INFO" "Comando de teste: ssh root@$ip_address -p $COWRIE_PORT"
    
    echo -e "\n${GREEN}${BOLD}✔ Instalação concluída com sucesso!${RESET}"
    echo -e "${WHITE}Agora você pode monitorar tentativas de acesso ao seu honeypot SSH.${RESET}"
}

# ------------------------------
# 🚀 FUNÇÃO PRINCIPAL
# ------------------------------
main() {
    init_logging
    print_header
    
    echo -e "${BOLD}${WHITE}Bem-vindo ao instalador do Cowrie Honeypot em Docker!${RESET}"
    echo -e "Este script irá:"
    echo -e "1. Instalar o Docker se necessário"
    echo -e "2. Configurar portas e firewall"
    echo -e "3. Baixar a imagem oficial do Cowrie"
    echo -e "4. Iniciar o container com configurações persistentes\n"
    
    pause
    
    # Executar etapas de instalação
    check_system
    install_docker
    configure_security
    install_cowrie
    
    show_dashboard
}

# ------------------------------
# � PONTO DE ENTRADA DO SCRIPT
# ------------------------------
if [ "$1" = "--help" ]; then
    print_header
    echo -e "${BOLD}Uso:${RESET}"
    echo -e "  $0          # Modo interativo"
    echo -e "  $0 --help   # Mostra esta ajuda"
    exit 0
else
    main
fi