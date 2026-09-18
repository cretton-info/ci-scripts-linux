#!/bin/bash
# ==============================================================================
# SCRIPT DE PROVISIONAMENTO E PÓS-INSTALAÇÃO (DEBIAN / UBUNTU / ZORIN)
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_real_user

echo "=========================================================="
echo " 🚀 PROVISIONAMENTO INICIAL DE SISTEMA "
echo "=========================================================="
echo "Usuário do sistema: $REAL_USER"
echo "Diretório Home: $USER_HOME"
echo "----------------------------------------------------------"

# 1. Atualização dos Repositórios e Sistema
log_info "1/5. Atualizando base de pacotes..."
# Não aborta em falha: um repositório de terceiros (PPA) fora do ar ou bloqueado
# não deve impedir o provisionamento com os repositórios essenciais que funcionaram.
apt-get update -y || log_warn "Alguns repositórios falharam ao atualizar, continuando com os que funcionaram."
apt-get upgrade -y || log_warn "Falha ao atualizar alguns pacotes instalados, continuando o provisionamento."

# 2. Instalação de Utilitários Essenciais de Sistema
log_info "2/5. Instalando utilitários essenciais de CLI e diagnóstico..."
PACOTES_ESSENCIAIS=(
    curl wget git htop net-tools
    ufw fail2ban ca-certificates
    gnupg lsb-release tree unzip
    software-properties-common ncdu
)
apt-get install -y "${PACOTES_ESSENCIAIS[@]}" || die "Falha ao instalar pacotes essenciais."

# 3. Configuração de Firewall Padrão (UFW)
log_info "3/5. Aplicando políticas de segurança do Firewall (UFW)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH Access'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable

# 4. Instalação da Engine Docker e Docker Compose
log_info "4/5. Verificando e instalando Docker / Docker Compose..."
if ! has_cmd docker; then
    log_info "Instalando Docker Engine via repositório oficial..."
    install -m 0755 -d /etc/apt/keyrings

    . /etc/os-release
    DOCKER_DISTRO="$ID"
    if [ "$DOCKER_DISTRO" != "ubuntu" ] && [ "$DOCKER_DISTRO" != "debian" ]; then
        DOCKER_DISTRO="ubuntu"
    fi

    curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc \
        || die "Falha ao baixar a chave GPG do Docker."
    chmod a+r /etc/apt/keyrings/docker.asc

    CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} ${CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y || die "Falha ao atualizar pacotes após adicionar repositório Docker."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
        || die "Falha ao instalar o Docker."

    usermod -aG docker "$REAL_USER"
    log_ok "Docker instalado e $REAL_USER adicionado ao grupo docker."
else
    log_ok "Docker já está instalado na máquina."
fi

# 5. Estrutura de Diretórios da Consultoria
log_info "5/5. Criando diretórios padrão de infraestrutura..."
su - "$REAL_USER" -c "mkdir -p ~/scripts ~/backups_sistema ~/docker_stacks"

apt-get autoremove -y && apt-get clean

echo -e "\n=========================================================="
log_ok "PROVISIONAMENTO CONCLUÍDO COM SUCESSO!"
echo "=========================================================="
echo "📌 O usuário '$REAL_USER' agora tem permissões do Docker."
echo "⚠️  Nota: faça logout e login novamente para ativar o grupo Docker."
echo "=========================================================="
