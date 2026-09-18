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

log_info()  { printf '%s[INFO]%s  %s\n' "$C_BLUE"  "$C_RESET" "$*"; }
log_ok()    { printf '%s[ OK ]%s  %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()  { printf '%s[WARN]%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[ERRO]%s  %s\n' "$C_RED"   "$C_RESET" "$*" >&2; }
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
