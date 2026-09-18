#!/bin/bash
# ==============================================================================
# PAINEL CENTRAL DE FERRAMENTAS DE INFRAESTRUTURA & TI
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

detect_real_user
SCRIPTS_DIR="${USER_HOME}/scripts"

pausa() {
    echo -e "\nPressione [ENTER] para voltar ao menu..."
    read -r
}

executar() {
    local script="$1" precisa_sudo="${2:-nao}"
    clear
    local caminho="${SCRIPTS_DIR}/${script}"
    if [ ! -f "$caminho" ]; then
        log_error "Script ${script} não encontrado em ${SCRIPTS_DIR}!"
        echo "Rode o install.sh do repositório ci-scripts-linux para instalar os scripts."
        pausa
        return
    fi
    if [ "$precisa_sudo" = "sudo" ]; then
        sudo bash "$caminho"
    else
        bash "$caminho"
    fi
    pausa
}

while true; do
    clear
    echo "=========================================================="
    echo " 🛠️  CENTRAL DE FERRAMENTAS DE INFRAESTRUTURA & TI "
    echo "=========================================================="
    echo " Host: $(hostname) | Usuário: $REAL_USER"
    echo "----------------------------------------------------------"
    echo " 1) 🔍 Saúde do Sistema (Health Check)"
    echo " 2) 📡 Varredura de Rede Local & Portas (Network Scanner)"
    echo " 3) 📊 Inventário Completo do Hardware & OS"
    echo " 4) 🧹 Manutenção, Limpeza & Atualização do Sistema"
    echo " 5) 💾 Executar Backup Multi-Perfil"
    echo " 6) 🔄 Restaurar Backup Interativo"
    echo " 7) 🚀 Provisionar Máquina (Setup Pós-Instalação)"
    echo "----------------------------------------------------------"
    echo " 0) ❌ Sair"
    echo "=========================================================="
    read -r -p "Escolha uma opção [0-7]: " OPCAO

    case "$OPCAO" in
        1) executar "health_check.sh" ;;
        2) executar "network_scanner.sh" ;;
        3) executar "inventario_universal.sh" ;;
        4) executar "manutencao_avancada.sh" sudo ;;
        5) executar "backup_multiperfil.sh" ;;
        6) executar "restaurar_backup.sh" sudo ;;
        7) executar "setup_pos_instalacao.sh" sudo ;;
        0)
            echo -e "\nSaindo... Até logo!"
            exit 0
            ;;
        *)
            log_error "Opção inválida!"
            sleep 1.5
            ;;
    esac
done
