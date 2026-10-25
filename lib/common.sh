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
# Ordem: CI_REAL_USER (override explícito) > SUDO_USER > dono do script quando
# roda como root sem sudo > usuário atual. O caso "root sem sudo" é o cron do
# root (/etc/cron.d, crontab -e como root): sem SUDO_USER, o usuário real virava
# o root e o backup ia pra /root/backups_sistema, com ~/Documentos de fora. Os
# scripts ficam em ~/scripts do usuário (install.sh faz chown), então o dono do
# arquivo é o usuário certo.
detect_real_user() {
    REAL_USER="${CI_REAL_USER:-}"
    if [ -z "$REAL_USER" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        REAL_USER="$SUDO_USER"
    fi
    if [ -z "$REAL_USER" ] && [ "$EUID" -eq 0 ]; then
        local script dono
        script=$(readlink -f "${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}" 2>/dev/null)
        dono=$(stat -c %U "$script" 2>/dev/null)
        if [ -n "$dono" ] && [ "$dono" != "root" ] && [ "$dono" != "UNKNOWN" ]; then
            REAL_USER="$dono"
        fi
    fi
    REAL_USER="${REAL_USER:-${USER:-$(id -un)}}"
    USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        USER_HOME="${HOME:-/root}"
    fi
}

# Lê variáveis de um arquivo KEY=VALOR sem executá-lo (nunca faz source: o arquivo
# pode ser do usuário comum e o script rodar como root). Só aceita os nomes passados
# como argumento, tira aspas simples ou duplas em volta do valor e não sobrescreve
# variável que já veio definida pelo ambiente (o ambiente tem prioridade).
# Uso: load_conf "/caminho/arquivo.conf" VAR1 VAR2 ...
load_conf() {
    local arquivo="$1"; shift
    [ -f "$arquivo" ] || return 0
    local linha chave valor permitido nome
    while IFS= read -r linha || [ -n "$linha" ]; do
        linha="${linha#"${linha%%[![:space:]]*}"}"
        case "$linha" in ''|'#'*) continue ;; esac
        [[ "$linha" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
        chave="${BASH_REMATCH[1]}"; valor="${BASH_REMATCH[2]}"
        permitido=0
        for nome in "$@"; do [ "$nome" = "$chave" ] && permitido=1 && break; done
        [ "$permitido" -eq 1 ] || continue
        [ -n "${!chave+x}" ] && continue
        if [[ "$valor" =~ ^\"(.*)\"$ ]] || [[ "$valor" =~ ^\'(.*)\'$ ]]; then
            valor="${BASH_REMATCH[1]}"
        fi
        printf -v "$chave" '%s' "$valor"
    done < "$arquivo"
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

# Roda rclone como o usuário real por trás do sudo, não como root — usa o
# rclone.conf de quem configurou os remotes (não o de root) e os arquivos
# enviados/baixados ficam com o dono certo, sem precisar de chown depois.
# Requer detect_real_user já chamado antes (usa REAL_USER). Rodando sem root,
# ou quando o usuário real é o próprio root, chama o rclone normalmente. Não
# depende de SUDO_USER: no cron do root ele não existe, mas REAL_USER sim.
# Uso: rclone_usuario copy origem destino
rclone_usuario() {
    if [ "$EUID" -eq 0 ] && [ "${REAL_USER:-root}" != "root" ]; then
        sudo -u "$REAL_USER" -H rclone "$@"
    else
        rclone "$@"
    fi
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
        "$(json_escape "$(hostname)")" "$(json_escape "$(basename "${0%.sh}")")" \
        "$(json_escape "$motivo")" "$(json_escape "$detalhe")" "$(date '+%Y-%m-%d %H:%M:%S')")

    if curl -fsS -m 10 -X POST -H 'Content-Type: application/json' -d "$payload" "$webhook" >/dev/null 2>&1; then
        date +%s > "$arquivo_estado" 2>/dev/null || true
        log_info "Alerta enviado via webhook: ${motivo} (${detalhe})"
    else
        log_warn "Falha ao enviar alerta via webhook para: ${motivo}"
    fi
}

# Marca que um script terminou de rodar com sucesso, gravando um timestamp em
# <pasta do log>/heartbeats/<nome>.last. Existe pra que outro processo (ex.:
# maintenance/verificar_agendamentos.sh) detecte se o cron parou de disparar —
# o alert_webhook só dispara de dentro do script, então não ajuda quando o
# problema é o cron nunca chamar o script. Chame só no caminho de sucesso,
# nunca em --dry-run nem depois de uma falha (senão o heartbeat mentiria).
# Uso: marcar_execucao_ok "nome_curto"
marcar_execucao_ok() {
    local nome="$1"
    local dir
    dir="$(dirname "${LOG_FILE:-/tmp/ci-scripts-linux-logs/x}")/heartbeats"
    mkdir -p "$dir" 2>/dev/null || dir="/tmp/ci-scripts-linux-heartbeats"
    mkdir -p "$dir" 2>/dev/null || return 0
    date +%s > "${dir}/${nome}.last" 2>/dev/null || true
}
