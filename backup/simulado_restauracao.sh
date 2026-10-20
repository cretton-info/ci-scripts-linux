#!/bin/bash
# ==============================================================================
# SIMULADO DE RESTAURAÇÃO — confere que os backups realmente restauram
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

detect_real_user

DESTINO_BASE="${USER_HOME}/backups_sistema"
ARQUIVO_CHAVE="${ARQUIVO_CHAVE:-etc/passwd}"
IDADE_MAX_DIAS="${IDADE_MAX_DIAS:-3}"

exibir_ajuda() {
    cat <<EOF
Uso: $0 [PERFIL]

Extrai o backup mais recente de um perfil (ou de todos os perfis encontrados,
se PERFIL for omitido) num diretório temporário, confere a integridade e a
presença de um arquivo-chave dentro dele, e apaga tudo em seguida. Não toca em
nada fora do diretório temporário — seguro pra rodar via cron sem supervisão.
Um backup nunca testado não é um backup, é só um .tar.gz.

  PERFIL            Nome da pasta em ~/backups_sistema/ (ex.: homelab). Se
                     omitido, roda o simulado para todos os perfis encontrados.

Variáveis de ambiente:
  ARQUIVO_CHAVE     Caminho (relativo à raiz do tar) que precisa existir no
                     backup pra ele ser considerado válido (padrão: etc/passwd,
                     presente em todo perfil porque /etc sempre é incluído)
  IDADE_MAX_DIAS    Idade máxima, em dias, do backup mais recente de cada
                     perfil (padrão: 3). Mais velho que isso conta como falha:
                     o backup parou de rodar (ou está gravando em outro lugar)
                     e o simulado estaria testando um arquivo antigo.
  WEBHOOK_URL       Se definida, alerta quando um simulado falha
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    exibir_ajuda
    exit 0
fi

if ! [[ "$IDADE_MAX_DIAS" =~ ^[0-9]+$ ]] || [ "$IDADE_MAX_DIAS" -lt 1 ]; then
    die "IDADE_MAX_DIAS inválido: '$IDADE_MAX_DIAS' (precisa ser um número inteiro >= 1)."
fi

[ -d "$DESTINO_BASE" ] || die "Diretório de backups não encontrado em: $DESTINO_BASE"

if [ -n "${1:-}" ]; then
    PERFIS=("$1")
else
    PERFIS=()
    while IFS= read -r -d '' d; do
        PERFIS+=("$(basename "$d")")
    done < <(find "$DESTINO_BASE" -mindepth 1 -maxdepth 1 -type d \
                ! -name '_seguranca_pre_restauracao' -print0)
fi

[ "${#PERFIS[@]}" -gt 0 ] || die "Nenhum perfil de backup encontrado em $DESTINO_BASE."

echo "=========================================================="
echo " 🧪 SIMULADO DE RESTAURAÇÃO — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="

FALHAS=0

for PERFIL in "${PERFIS[@]}"; do
    echo ""
    echo "── Perfil: ${PERFIL} ──────────────────────────────"
    DIR_PERFIL="${DESTINO_BASE}/${PERFIL}"

    if [ ! -d "$DIR_PERFIL" ]; then
        log_warn "Perfil '${PERFIL}' não encontrado em ${DESTINO_BASE}."
        FALHAS=$((FALHAS + 1))
        alert_webhook "simulado_restauracao_${PERFIL}" "Perfil '${PERFIL}' não encontrado em ${DESTINO_BASE}."
        continue
    fi

    ARQUIVOS=()
    while IFS= read -r -d '' f; do
        ARQUIVOS+=("$f")
    done < <(find "$DIR_PERFIL" -maxdepth 1 -name "backup_${PERFIL}_*.tar.gz" -type f -printf '%T@ %p\0' \
                | sort -z -rn | sed -z 's/^[^ ]* //')

    if [ "${#ARQUIVOS[@]}" -eq 0 ]; then
        log_warn "Nenhum backup .tar.gz encontrado para o perfil '${PERFIL}'."
        FALHAS=$((FALHAS + 1))
        alert_webhook "simulado_restauracao_${PERFIL}" "Nenhum backup .tar.gz encontrado para o perfil '${PERFIL}'."
        continue
    fi

    ARQUIVO="${ARQUIVOS[0]}"
    log_info "Backup selecionado: $(basename "$ARQUIVO")"

    # Backup velho é falha mesmo que restaure: sem isso o simulado "passa"
    # testando sempre o mesmo arquivo antigo enquanto o backup de verdade parou
    # (ou foi parar em outra pasta -- ex.: cron do root gravando em /root).
    IDADE_DIAS=$(( ( $(date +%s) - $(stat -c %Y "$ARQUIVO") ) / 86400 ))
    if [ "$IDADE_DIAS" -gt "$IDADE_MAX_DIAS" ]; then
        log_warn "Backup mais recente do perfil '${PERFIL}' tem ${IDADE_DIAS} dia(s) (limite: ${IDADE_MAX_DIAS}) — o backup parou de rodar?"
        FALHAS=$((FALHAS + 1))
        alert_webhook "simulado_restauracao_${PERFIL}" "Backup mais recente do perfil '${PERFIL}' tem ${IDADE_DIAS} dia(s) (limite: ${IDADE_MAX_DIAS})."
    fi

    # Mesma verificação de integridade do restaurar_backup.sh: checksum se
    # existir (mais confiável), senão teste de leitura do tar como fallback.
    CHECKSUM="${ARQUIVO}.sha256"
    INTEGRO=1
    if [ -f "$CHECKSUM" ]; then
        if ! (cd "$(dirname "$ARQUIVO")" && sha256sum -c "$(basename "$CHECKSUM")") >/dev/null 2>&1; then
            INTEGRO=0
            log_warn "Checksum SHA-256 não confere para $(basename "$ARQUIVO")."
            alert_webhook "simulado_restauracao_${PERFIL}" "Checksum não confere em $(basename "$ARQUIVO")."
        fi
    elif ! tar -tzf "$ARQUIVO" >/dev/null 2>&1; then
        INTEGRO=0
        log_warn "Não foi possível ler $(basename "$ARQUIVO") (sem checksum salvo)."
        alert_webhook "simulado_restauracao_${PERFIL}" "Não foi possível ler $(basename "$ARQUIVO") (sem checksum salvo)."
    fi

    if [ "$INTEGRO" -eq 0 ]; then
        FALHAS=$((FALHAS + 1))
        continue
    fi
    log_ok "Integridade OK."

    TMP_DIR=$(mktemp -d)

    if ! tar -xzf "$ARQUIVO" -C "$TMP_DIR" 2>/dev/null; then
        log_warn "Falha ao extrair $(basename "$ARQUIVO") no simulado."
        FALHAS=$((FALHAS + 1))
        alert_webhook "simulado_restauracao_${PERFIL}" "Falha ao extrair $(basename "$ARQUIVO") no simulado de restauração."
        rm -rf "$TMP_DIR"
        continue
    fi

    if [ -e "${TMP_DIR}/${ARQUIVO_CHAVE}" ]; then
        log_ok "Arquivo-chave '${ARQUIVO_CHAVE}' presente no backup extraído."
    else
        log_warn "Arquivo-chave '${ARQUIVO_CHAVE}' NÃO encontrado no backup extraído."
        FALHAS=$((FALHAS + 1))
        alert_webhook "simulado_restauracao_${PERFIL}" "Arquivo-chave '${ARQUIVO_CHAVE}' ausente no backup extraído ($(basename "$ARQUIVO"))."
    fi

    rm -rf "$TMP_DIR"
done

echo ""
echo "=========================================================="
if [ "$FALHAS" -eq 0 ]; then
    log_ok "Simulado de restauração concluído sem falhas (${#PERFIS[@]} perfil(is) testado(s))."
    marcar_execucao_ok "simulado_restauracao"
else
    log_error "Simulado de restauração encontrou ${FALHAS} problema(s) — ver acima."
fi
echo "=========================================================="

[ "$FALHAS" -eq 0 ]
