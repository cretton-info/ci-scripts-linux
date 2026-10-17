#!/bin/bash
# ==============================================================================
# ATUALIZAÇÃO AUTOMÁTICA DO SISTEMA (apt update + apt full-upgrade)
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

# Marcador gravado ao final da linha do crontab criada por --agendar, pra achar
# e substituir (ou remover) só essa linha sem tocar no resto do crontab do root.
MARCADOR_CRON="ci-scripts-linux:atualizar_sistema"

exibir_ajuda() {
    cat <<EOF
Uso: sudo $0 [--dry-run | --agendar | --desagendar]

Sem argumentos: roda "apt-get update" + "apt-get full-upgrade" agora, sem interação
(seguro pra cron). Só isso — não remove pacotes, não limpa cache, não toca em
Docker/Flatpak/Snap (pra manutenção completa, veja manutencao_avancada.sh).

Opções:
  --dry-run      Mostra o que seria atualizado (apt-get full-upgrade -s), sem
                 instalar nada de verdade.
  --agendar      Assistente interativo: agenda esta atualização no crontab do
                 root (diária ou semanal, no horário escolhido). Rodar de novo
                 substitui o agendamento anterior, não duplica.
  --desagendar   Remove o agendamento criado por --agendar, se houver.
  -h, --help     Esta ajuda.
EOF
}

for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
        exibir_ajuda
        exit 0
    fi
done

require_root
detect_real_user

DRY_RUN=0
ACAO=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --agendar) ACAO="agendar" ;;
        --desagendar) ACAO="desagendar" ;;
    esac
done

# Remove a linha agendada por --agendar, se existir. Não falha se não houver
# nenhuma (idempotente — seguro chamar de novo, ou antes de recriar o agendamento).
remover_agendamento() {
    local atual
    atual=$(crontab -l 2>/dev/null || true)
    if ! printf '%s\n' "$atual" | grep -q "$MARCADOR_CRON"; then
        log_warn "Nenhum agendamento de $(basename "$0") encontrado no crontab do root."
        return 0
    fi
    printf '%s\n' "$atual" | grep -v "$MARCADOR_CRON" | crontab -
    log_ok "Agendamento removido do crontab do root."
}

# Assistente interativo: pergunta frequência (diária/semanal) e horário, monta a
# linha de cron e substitui qualquer agendamento anterior deste script (pelo
# marcador), sem afetar outras linhas do crontab do root.
agendar_cron() {
    echo "=========================================================="
    echo " 🗓️  AGENDAR ATUALIZAÇÃO AUTOMÁTICA (apt update + full-upgrade)"
    echo "=========================================================="
    echo "1) Diária"
    echo "2) Semanal"
    echo "----------------------------------------------------------"
    read -r -p "Frequência [1-2]: " FREQ

    read -r -p "Horário (HH:MM, 24h) [03:00]: " HORARIO
    HORARIO="${HORARIO:-03:00}"
    [[ "$HORARIO" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "Horário inválido — use HH:MM, ex.: 03:00."
    HORA="${HORARIO%%:*}"
    MINUTO="${HORARIO##*:}"

    case "$FREQ" in
        1)
            CRON_TEMPO="${MINUTO} ${HORA} * * *"
            DESC="todo dia às ${HORARIO}"
            ;;
        2)
            echo "Dia da semana: 0=domingo 1=segunda 2=terça 3=quarta 4=quinta 5=sexta 6=sábado"
            read -r -p "Dia [0-6]: " DIA
            [[ "$DIA" =~ ^[0-6]$ ]] || die "Dia da semana inválido (use um número de 0 a 6)."
            CRON_TEMPO="${MINUTO} ${HORA} * * ${DIA}"
            DESC="toda semana (dia ${DIA}) às ${HORARIO}"
            ;;
        *)
            die "Opção de frequência inválida."
            ;;
    esac

    local script_absoluto
    script_absoluto="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
    local linha="${CRON_TEMPO} ${script_absoluto} > /dev/null 2>&1 # ${MARCADOR_CRON}"

    ( crontab -l 2>/dev/null | grep -v "$MARCADOR_CRON"; printf '%s\n' "$linha" ) | crontab -
    log_ok "Agendado: atualização automática ${DESC}."
    echo "Linha adicionada ao crontab do root:"
    echo "  $linha"
    log_info "Pra conferir depois: sudo crontab -l | grep ${MARCADOR_CRON}"
    log_info "Pra cancelar: sudo $(basename "$script_absoluto") --desagendar"
}

if [ "$ACAO" = "agendar" ]; then
    agendar_cron
    exit 0
elif [ "$ACAO" = "desagendar" ]; then
    remover_agendamento
    exit 0
fi

echo "=========================================================="
if [ "$DRY_RUN" -eq 1 ]; then
    echo " 📦 ATUALIZAÇÃO DO SISTEMA (--dry-run: só mostra, não altera nada) — $(hostname)"
else
    echo " 📦 ATUALIZAÇÃO DO SISTEMA — $(hostname)"
fi
echo "=========================================================="

FALHOU=0

log_info "Atualizando lista de pacotes (apt-get update)..."
apt-get update -y || log_warn "Alguns repositórios falharam ao atualizar, continuando com os que funcionaram."

if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Simulando full-upgrade (apt-get full-upgrade -s), nada será instalado:"
    apt-get full-upgrade -s | grep -E '^(Inst|Remv|Conf)' || echo "  (nada a atualizar)"
else
    log_info "Aplicando atualizações (apt-get full-upgrade)..."
    # DEBIAN_FRONTEND=noninteractive + force-confdef/force-confold: mantém a
    # config atual em caso de pacote com arquivo de configuração modificado, em
    # vez de ficar esperando uma resposta que nunca vem rodando via cron.
    if DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y \
        -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"; then
        log_ok "Atualização concluída."
        marcar_execucao_ok "atualizar_sistema"
    else
        FALHOU=1
        log_error "apt-get full-upgrade falhou."
        alert_webhook "atualizacao_full_upgrade" "$(hostname): apt-get full-upgrade falhou durante a atualização automática."
    fi
fi

echo ""
if [ -f /var/run/reboot-required ]; then
    echo "⚠️  Atualizações críticas aplicadas! A reinicialização do sistema é recomendada."
    cat /var/run/reboot-required.pkgs 2>/dev/null || true
else
    echo "✅ Não é necessário reiniciar o sistema no momento."
fi
echo "=========================================================="

[ "$FALHOU" -eq 0 ] || exit 1
