#!/bin/bash
# ==============================================================================
# SCRIPT DE MANUTENÇÃO, LIMPEZA & ATUALIZAÇÃO DO SISTEMA
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_real_user

AUTO_YES="${AUTO_YES:-0}"
for arg in "$@"; do
    [ "$arg" = "--yes" ] || [ "$arg" = "-y" ] && AUTO_YES=1
done

JOURNAL_MAX_SIZE="${JOURNAL_MAX_SIZE:-200M}"
JOURNAL_MAX_AGE="${JOURNAL_MAX_AGE:-30d}"

echo "=========================================================="
echo " 🧹 MANUTENÇÃO E LIMPEZA DO SISTEMA — $(hostname)"
echo "=========================================================="

DISCO_ANTES=$(df -h / | tail -n1 | awk '{print $4}')

log_info "1/9. Atualizando pacotes do sistema (full-upgrade)..."
apt-get update -y || log_warn "Alguns repositórios falharam ao atualizar, continuando com os que funcionaram."
apt-get full-upgrade -y || log_warn "Falha ao atualizar alguns pacotes instalados, continuando a manutenção."

log_info "2/9. Verificando e corrigindo pacotes quebrados..."
apt-get install -f -y || log_warn "Falha ao corrigir dependências quebradas."
apt-get check || log_warn "apt-get check reportou inconsistências."

log_info "3/9. Removendo pacotes e dependências não utilizados (com --purge)..."
apt-get autoremove --purge -y || log_warn "Falha ao remover pacotes não utilizados."
apt-get autoclean -y || true

if has_cmd journalctl; then
    log_info "4/9. Limitando logs do journal a ${JOURNAL_MAX_SIZE} / ${JOURNAL_MAX_AGE}..."
    journalctl --vacuum-size="$JOURNAL_MAX_SIZE" --vacuum-time="$JOURNAL_MAX_AGE" || log_warn "Falha ao limpar logs do journal."
else
    log_warn "4/9. journalctl não encontrado, pulando limpeza de logs."
fi

if has_cmd flatpak; then
    log_info "5/9. Removendo runtimes Flatpak não utilizados..."
    flatpak uninstall --unused -y || log_warn "Falha ao limpar Flatpak."
else
    log_info "5/9. Flatpak não instalado, pulando."
fi

if has_cmd snap; then
    log_info "6/9. Limpando cache e revisões antigas do Snap..."
    rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
        snap remove "$snapname" --revision="$revision" 2>/dev/null || true
    done
else
    log_info "6/9. Snap não instalado, pulando."
fi

if has_cmd docker; then
    echo ""
    echo "🐳 O comando abaixo removerá imagens, redes e cache de build do Docker não usados"
    echo "   por nenhum contêiner em execução (não afeta contêineres nem volumes ativos):"
    docker system df 2>/dev/null || true
    if [ "$AUTO_YES" -eq 1 ] || confirm "7/9. Executar 'docker system prune' agora?"; then
        log_info "Limpando recursos Docker não utilizados..."
        docker system prune -f
    else
        log_warn "7/9. Limpeza do Docker pulada pelo usuário."
    fi
else
    log_warn "7/9. Docker não encontrado, pulando limpeza de contêineres."
fi

log_info "8/9. Limpando lixeira e miniaturas do usuário ${REAL_USER}..."
rm -rf "${USER_HOME}/.local/share/Trash/"* "${USER_HOME}/.cache/thumbnails/"* 2>/dev/null || true

if has_cmd fstrim; then
    log_info "9/9. Otimizando SSDs (TRIM)..."
    fstrim -av 2>/dev/null || log_warn "fstrim falhou (normal se o disco não suportar TRIM, ex.: HD comum ou disco virtual)."
else
    log_info "9/9. fstrim não disponível, pulando otimização de SSD."
fi

apt-get clean

DISCO_DEPOIS=$(df -h / | tail -n1 | awk '{print $4}')

echo -e "\n=========================================================="
log_ok "MANUTENÇÃO CONCLUÍDA!"
echo "=========================================================="
echo "📊 Memória:"
free -h
echo "📀 Espaço livre em / antes:  $DISCO_ANTES"
echo "📀 Espaço livre em / depois: $DISCO_DEPOIS"

echo -e "\n🔍 Verificação de reinicialização:"
if [ -f /var/run/reboot-required ]; then
    echo "⚠️  Atualizações críticas aplicadas! A reinicialização do sistema é recomendada."
    cat /var/run/reboot-required.pkgs 2>/dev/null || true
else
    echo "✅ Não é necessário reiniciar o sistema no momento."
fi
echo "=========================================================="
