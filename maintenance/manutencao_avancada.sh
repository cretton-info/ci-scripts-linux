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
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_YES=1 ;;
        --dry-run) DRY_RUN=1 ;;
    esac
done

JOURNAL_MAX_SIZE="${JOURNAL_MAX_SIZE:-200M}"
JOURNAL_MAX_AGE="${JOURNAL_MAX_AGE:-30d}"

echo "=========================================================="
if [ "$DRY_RUN" -eq 1 ]; then
    echo " 🧹 MANUTENÇÃO (--dry-run: só mostra, não altera nada) — $(hostname)"
else
    echo " 🧹 MANUTENÇÃO E LIMPEZA DO SISTEMA — $(hostname)"
fi
echo "=========================================================="

DISCO_ANTES=$(df -h / | tail -n1 | awk '{print $4}')

log_info "1/9. Atualizando pacotes do sistema (full-upgrade)..."
apt-get update -y || log_warn "Alguns repositórios falharam ao atualizar, continuando com os que funcionaram."
if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Simulando full-upgrade (apt-get full-upgrade -s, nada é instalado):"
    apt-get full-upgrade -s | grep -E '^(Inst|Remv|Conf)' || echo "  (nada a atualizar)"
elif ! apt-get full-upgrade -y; then
    log_warn "Falha ao atualizar alguns pacotes instalados, continuando a manutenção."
    alert_webhook "manutencao_full_upgrade" "$(hostname): apt-get full-upgrade falhou durante a manutenção."
fi

log_info "2/9. Verificando e corrigindo pacotes quebrados..."
if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Simulando correção de dependências (apt-get install -f -s):"
    apt-get install -f -s | grep -E '^(Inst|Remv|Conf)' || echo "  (nada quebrado)"
elif ! apt-get install -f -y; then
    log_warn "Falha ao corrigir dependências quebradas."
    alert_webhook "manutencao_deps_quebradas" "$(hostname): apt-get install -f não conseguiu corrigir dependências quebradas."
fi
apt-get check || log_warn "apt-get check reportou inconsistências."

log_info "3/9. Removendo pacotes e dependências não utilizados (com --purge)..."
if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Pacotes que seriam removidos (apt-get autoremove --purge -s):"
    apt-get autoremove --purge -s | grep -E '^Remv' || echo "  (nenhum)"
else
    apt-get autoremove --purge -y || log_warn "Falha ao remover pacotes não utilizados."
    apt-get autoclean -y || true
fi

if has_cmd journalctl; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] 4/9. Logs do journal ocupam hoje: $(journalctl --disk-usage 2>/dev/null | tr -d '\n')"
        log_info "[DRY-RUN] Não reduzido para ${JOURNAL_MAX_SIZE} / ${JOURNAL_MAX_AGE}."
    else
        log_info "4/9. Limitando logs do journal a ${JOURNAL_MAX_SIZE} / ${JOURNAL_MAX_AGE}..."
        journalctl --vacuum-size="$JOURNAL_MAX_SIZE" --vacuum-time="$JOURNAL_MAX_AGE" || log_warn "Falha ao limpar logs do journal."
    fi
else
    log_warn "4/9. journalctl não encontrado, pulando limpeza de logs."
fi

if has_cmd flatpak; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] 5/9. Flatpak: 'flatpak uninstall --unused' não executado."
    else
        log_info "5/9. Removendo runtimes Flatpak não utilizados..."
        flatpak uninstall --unused -y || log_warn "Falha ao limpar Flatpak."
    fi
else
    log_info "5/9. Flatpak não instalado, pulando."
fi

if has_cmd snap; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] 6/9. Revisões desabilitadas do Snap que seriam removidas:"
        snap list --all 2>/dev/null | awk '/disabled/{print "  " $1, $3}' | grep . || echo "  (nenhuma)"
        log_info "[DRY-RUN] Cache do Snap (/var/lib/snapd/cache) não seria limpo."
    else
        log_info "6/9. Limpando cache e revisões antigas do Snap..."
        rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
        snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
            snap remove "$snapname" --revision="$revision" 2>/dev/null || true
        done
    fi
else
    log_info "6/9. Snap não instalado, pulando."
fi

if has_cmd docker; then
    echo ""
    echo "🐳 O comando abaixo removerá imagens, redes e cache de build do Docker não usados"
    echo "   por nenhum contêiner em execução (não afeta contêineres nem volumes ativos):"
    docker system df 2>/dev/null || true
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] 7/9. 'docker system prune' não seria executado."
    elif [ "$AUTO_YES" -eq 1 ] || confirm "7/9. Executar 'docker system prune' agora?"; then
        log_info "Limpando recursos Docker não utilizados..."
        docker system prune -f
    else
        log_warn "7/9. Limpeza do Docker pulada pelo usuário."
    fi
else
    log_warn "7/9. Docker não encontrado, pulando limpeza de contêineres."
fi

if [ "$DRY_RUN" -eq 1 ]; then
    TAM_LIXO=$(du -sch "${USER_HOME}/.local/share/Trash" "${USER_HOME}/.cache/thumbnails" 2>/dev/null | tail -n1 | awk '{print $1}')
    log_info "[DRY-RUN] 8/9. Lixeira e miniaturas de ${REAL_USER} não seriam apagadas (~${TAM_LIXO:-0} juntas)."
else
    log_info "8/9. Limpando lixeira e miniaturas do usuário ${REAL_USER}..."
    rm -rf "${USER_HOME}/.local/share/Trash/"* "${USER_HOME}/.cache/thumbnails/"* 2>/dev/null || true
fi

if has_cmd fstrim; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] 9/9. fstrim não seria executado."
    else
        log_info "9/9. Otimizando SSDs (TRIM)..."
        fstrim -av 2>/dev/null || log_warn "fstrim falhou (normal se o disco não suportar TRIM, ex.: HD comum ou disco virtual)."
    fi
else
    log_info "9/9. fstrim não disponível, pulando otimização de SSD."
fi

[ "$DRY_RUN" -eq 1 ] || apt-get clean

DISCO_DEPOIS=$(df -h / | tail -n1 | awk '{print $4}')

echo -e "\n=========================================================="
if [ "$DRY_RUN" -eq 1 ]; then
    log_ok "DRY-RUN CONCLUÍDO — nenhuma alteração foi feita no sistema."
else
    log_ok "MANUTENÇÃO CONCLUÍDA!"
fi
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
