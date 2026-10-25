#!/bin/bash
# ==============================================================================
# LISTA OS AGENDAMENTOS (CRONTAB) RELACIONADOS AO CI-SCRIPTS-LINUX
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
# Visão unificada: mostra de uma vez só as linhas do crontab (do root e do
# usuário real) que chamam algum script deste repositório, sem precisar lembrar
# de rodar "crontab -l | grep ..." manualmente pra auditar uma máquina.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
        cat <<EOF
Uso: sudo $0

Lista as linhas do crontab do root e do usuário real que chamam algum script
deste repositório (backup, restauração, atualização automática, manutenção,
monitoramento, verificação de agendamentos). Só leitura, não altera nada.
EOF
        exit 0
    fi
done

require_root
detect_real_user

# Qualquer linha que chame um dos scripts instalados por install.sh em ~/scripts/.
PADRAO='/(backup_multiperfil|restaurar_backup|simulado_restauracao|atualizar_sistema|verificar_agendamentos|manutencao_avancada|health_check|network_scanner|status_frota|inventario_universal|setup_pos_instalacao)\.sh'

echo "=========================================================="
echo " ⏰ AGENDAMENTOS DO CI-SCRIPTS-LINUX — $(hostname)"
echo "=========================================================="

echo ""
echo "── Crontab do root ──────────────────────────────────────"
LINHAS_ROOT=$(crontab -l 2>/dev/null | grep -E "$PADRAO" || true)
if [ -n "$LINHAS_ROOT" ]; then
    echo "$LINHAS_ROOT"
else
    echo "  (nenhum agendamento encontrado)"
fi

if [ "$REAL_USER" != "root" ]; then
    echo ""
    echo "── Crontab de ${REAL_USER} ──────────────────────────────"
    LINHAS_USUARIO=$(crontab -u "$REAL_USER" -l 2>/dev/null | grep -E "$PADRAO" || true)
    if [ -n "$LINHAS_USUARIO" ]; then
        echo "$LINHAS_USUARIO"
    else
        echo "  (nenhum agendamento encontrado)"
    fi
fi

echo ""
echo "=========================================================="
echo "Pra agendar a atualização automática: sudo ~/scripts/atualizar_sistema.sh --agendar"
echo "Pra conferir se os agendamentos ainda estão rodando de verdade: sudo ~/scripts/verificar_agendamentos.sh"
echo "=========================================================="
