#!/bin/bash
# shellcheck shell=bash
# ==============================================================================
# lib/common.sh — funções compartilhadas pelos scripts de ci-scripts-linux
# Uso: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# ==============================================================================

if [ -t 1 ]; then
    C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[0;34m'; C_RESET=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi

# Log automático de avisos/erros em arquivo, além da saída no terminal.
# Local: CI_LOG_DIR se definido; senão /var/log/ci-scripts-linux (root) ou
# ~/.local/state/ci-scripts-linux/logs (usuário comum); com fallback pra /tmp
# se nenhum dos dois for gravável.
_ci_log_setup() {
    local dir="${CI_LOG_DIR:-}"
    if [ -z "$dir" ]; then
        if [ "$EUID" -eq 0 ]; then
            dir="/var/log/ci-scripts-linux"
        else
            dir="${HOME:-/tmp}/.local/state/ci-scripts-linux/logs"
        fi
    fi
    mkdir -p "$dir" 2>/dev/null || dir="/tmp/ci-scripts-linux-logs"
    mkdir -p "$dir" 2>/dev/null || dir=""

    if [ -n "$dir" ]; then
        LOG_FILE="${dir}/$(basename "${0%.sh}").log"
    else
        LOG_FILE=""
    fi
}
_ci_log_setup

_log_to_file() {
    [ -n "${LOG_FILE:-}" ] || return 0
    printf '%s [%s] (pid %s) %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$$" "$2" >> "$LOG_FILE" 2>/dev/null
}

log_info()  { printf '%s[INFO]%s  %s\n' "$C_BLUE"  "$C_RESET" "$*"; }
log_ok()    { printf '%s[ OK ]%s  %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()  { printf '%s[WARN]%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; _log_to_file "WARN" "$*"; }
log_error() { printf '%s[ERRO]%s  %s\n' "$C_RED"   "$C_RESET" "$*" >&2; _log_to_file "ERRO" "$*"; }
die()       { log_error "$*"; exit 1; }

# Aborta se não estiver rodando como root/sudo.
require_root() {
    if [ "$EUID" -ne 0 ]; then
        die "Este script precisa ser executado com sudo. Uso: sudo $0"
    fi
}

# Preenche REAL_USER e USER_HOME com o usuário real por trás do sudo,
# sem usar eval (evita risco de injeção via variáveis de ambiente).
detect_real_user() {
    REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
    USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        USER_HOME="${HOME:-/root}"
    fi
}

# Pergunta de confirmação s/N. Retorna 0 para sim, 1 para não.
confirm() {
    local prompt="${1:-Confirma?}" resposta
    read -r -p "$prompt (s/N): " resposta
    [[ "$resposta" =~ ^[Ss]$ ]]
}

# Verifica se um comando existe no PATH.
has_cmd() {
    command -v "$1" &>/dev/null
}

# Escapa uma string para entrar com segurança dentro de um valor JSON
# (aspas, barra invertida, quebra de linha e tabulação). Uso:
# printf '{"campo":"%s"}' "$(json_escape "$valor")"
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/}"
    # Remove qualquer outro caractere de controle restante (ex.: códigos de cor
    # ANSI de programas que não se comportam bem com --version) — JSON exige
    # que sejam escapados, e não valem a pena preservar num campo de texto.
    printf '%s' "$s" | tr -d '\000-\037'
}

# Envia um alerta em JSON para WEBHOOK_URL (se definida), com cooldown por motivo
# (evita repetir o mesmo alerta enquanto o problema persiste, ex.: o mesmo cron
# rodando de novo antes de alguém resolver). Usado por qualquer script para
# reportar falhas sem duplicar essa lógica em cada um.
# Uso: alert_webhook "motivo_curto_sem_espacos" "detalhe legível pra humano"
alert_webhook() {
    local motivo="$1" detalhe="$2"
    local webhook="${WEBHOOK_URL:-}"
    [ -n "$webhook" ] || return 0
    if ! has_cmd curl; then
        log_warn "WEBHOOK_URL definido mas curl não encontrado — alerta não enviado."
        return 0
    fi

    local cooldown_horas="${ALERTA_COOLDOWN_HORAS:-6}"
    local estado_dir chave arquivo_estado
    estado_dir="$(dirname "${LOG_FILE:-/tmp/ci-scripts-linux-logs/x}")/alertas"
    mkdir -p "$estado_dir" 2>/dev/null || estado_dir="/tmp/ci-scripts-linux-alertas"
    mkdir -p "$estado_dir" 2>/dev/null || true
    chave=$(echo "$motivo" | tr -cs '[:alnum:]' '_')
    arquivo_estado="${estado_dir}/${chave}.last"

    if [ -f "$arquivo_estado" ]; then
        local ultimo_ts agora_ts
        ultimo_ts=$(cat "$arquivo_estado" 2>/dev/null || echo 0)
        agora_ts=$(date +%s)
        if [ $(( (agora_ts - ultimo_ts) / 3600 )) -lt "$cooldown_horas" ]; then
            return 0
        fi
    fi

    local payload
    payload=$(printf '{"hostname":"%s","script":"%s","motivo":"%s","detalhe":"%s","data":"%s"}' \
        "$(hostname)" "$(basename "${0%.sh}")" "$motivo" "$detalhe" "$(date '+%Y-%m-%d %H:%M:%S')")

    if curl -fsS -m 10 -X POST -H 'Content-Type: application/json' -d "$payload" "$webhook" >/dev/null 2>&1; then
        date +%s > "$arquivo_estado" 2>/dev/null || true
        log_info "Alerta enviado via webhook: ${motivo} (${detalhe})"
    else
        log_warn "Falha ao enviar alerta via webhook para: ${motivo}"
    fi
}
