#!/bin/bash
# ==============================================================================
# SCRIPT DE BACKUP ROTATIVO MULTI-PERFIL
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

detect_real_user

DESTINO_BASE="${USER_HOME}/backups_sistema"
RETENCAO_DIAS="${RETENCAO_DIAS:-7}"
DATA=$(date +%Y-%m-%d_%H%M%S)

# Guard-rail: RETENCAO_DIAS inválido ou menor que 1 apagaria backups recém-criados
# (inclusive o desta própria execução) na primeira rotação. Recusa em vez de arriscar.
if ! [[ "$RETENCAO_DIAS" =~ ^[0-9]+$ ]] || [ "$RETENCAO_DIAS" -lt 1 ]; then
    die "RETENCAO_DIAS inválido: '$RETENCAO_DIAS' (precisa ser um número inteiro >= 1)."
fi

exibir_ajuda() {
    cat <<EOF
Uso: sudo $0 [PERFIL] [--dry-run]

Opções de Perfil de Backup:
  1, docs      Arquivos do Usuário e Documentos (~/Documentos + /etc)
  2, homelab   Dumps de Banco / Home Lab / Web (/var/www + /opt/docker-containers + /etc)
  3, scripts   Projetos de Automação e Scripts (~/scripts + /etc)
  4, tudo      Backup Completo (todas as origens acima)
  --menu       Exibe o menu interativo para seleção
  --dry-run    Mostra o que seria feito (diretórios, exclusões, tamanho
               estimado) sem criar, enviar ou apagar nada de verdade

Variáveis de ambiente:
  RETENCAO_DIAS     Dias de retenção dos backups antigos (padrão: 7)
  EXCLUDE_PATTERNS  Padrões extras a excluir do backup, separados por vírgula
                    (ex.: "*.log,cache/*"). Somados aos padrões padrão:
                    .git, node_modules, __pycache__, .cache
  RCLONE_REMOTO     Remote:caminho do rclone (ex.: "b2:meu-bucket/cliente-x").
                    Se definido, envia o backup e o checksum recém-criados
                    para lá após o backup local (requer rclone configurado).
                    Aceita mais de um destino separados por vírgula (ex.:
                    "b2:bucket-x,gdrive:pasta-y") pra redundância 3-2-1 —
                    cada um é enviado de forma independente, e a falha num
                    não impede o envio pros outros.
  RCLONE_FLAGS      Flags extras passadas ao rclone (ex.: "--fast-list").
EOF
}

# -h/--help nao precisa de root, mesmo sendo o primeiro uso do script.
for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
        exibir_ajuda
        exit 0
    fi
done

# Todos os perfis incluem /etc (chaves SSH, segredos do Dokploy, /etc/shadow
# etc.) - sem root o tar falha com "Permission denied" em dezenas de arquivos
# e sai com codigo 2, que o script trata como erro fatal (ver mais abaixo) e
# apaga o archive parcial. Antes isso so aparecia como um "codigo tar: 2"
# sem explicacao nenhuma - falha real encontrada testando o painel no ac8
# em 2026-10-01. Documentado no uso ("sudo $0 [PERFIL]") mas nunca imposto.
require_root

# --dry-run pode vir em qualquer posição junto do perfil (ex.: "homelab --dry-run").
DRY_RUN=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=1
    else
        ARGS+=("$arg")
    fi
done
MODO="${ARGS[0]:-}"

if [ -z "$MODO" ] || [ "$MODO" == "--menu" ]; then
    echo "=========================================================="
    echo " 📦 SELEÇÃO DE PERFIL DE BACKUP ROTATIVO "
    echo "=========================================================="
    echo "1) 📄 Arquivos do Usuário / Documentos (/etc + ~/Documentos)"
    echo "2) 🐳 Dumps / Home Lab / Web (/etc + /var/www + /opt/docker-containers)"
    echo "3) ⚙️  Projetos de Automação / Scripts (/etc + ~/scripts)"
    echo "4) 🌐 COMPLETO (todas as opções anteriores)"
    echo "----------------------------------------------------------"
    read -r -p "Escolha uma opção [1-4]: " OPCAO
else
    OPCAO="$MODO"
fi

case "$OPCAO" in
    1|docs|documentos)
        NOME_PERFIL="documentos"
        ORIGEM_SOLICITADA=("/etc" "${USER_HOME}/Documentos")
        ;;
    2|homelab|docker)
        NOME_PERFIL="homelab"
        ORIGEM_SOLICITADA=("/etc" "/var/www" "/opt/docker-containers")
        ;;
    3|scripts|automacao)
        NOME_PERFIL="scripts"
        ORIGEM_SOLICITADA=("/etc" "${USER_HOME}/scripts")
        ;;
    4|tudo|completo)
        NOME_PERFIL="completo"
        ORIGEM_SOLICITADA=("/etc" "${USER_HOME}/Documentos" "/var/www" "/opt/docker-containers" "${USER_HOME}/scripts")
        ;;
    -h|--help)
        exibir_ajuda
        exit 0
        ;;
    *)
        log_error "Opção inválida!"
        exibir_ajuda
        exit 1
        ;;
esac

# Lock de concorrência: evita que duas execuções do mesmo perfil rodem ao mesmo tempo
# (ex.: cron disparando de novo enquanto a execução anterior ainda compacta uma origem grande).
# Não faz sentido travar nada no --dry-run: ele não escreve em lugar nenhum.
if [ "$DRY_RUN" -eq 0 ] && has_cmd flock; then
    mkdir -p "$DESTINO_BASE"
    LOCK_FILE="${DESTINO_BASE}/.lock_${NOME_PERFIL}"
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        die "Já existe um backup do perfil '${NOME_PERFIL}' em andamento (lock: $LOCK_FILE). Abortando para evitar sobreposição."
    fi
elif [ "$DRY_RUN" -eq 0 ]; then
    log_warn "Comando 'flock' não encontrado — não é possível evitar execuções sobrepostas deste script."
fi

DESTINO_FINAL="${DESTINO_BASE}/${NOME_PERFIL}"
[ "$DRY_RUN" -eq 1 ] || mkdir -p "$DESTINO_FINAL"
ARQUIVO_FINAL="${DESTINO_FINAL}/backup_${NOME_PERFIL}_${DATA}.tar.gz"

echo "=========================================="
echo " 📦 INICIANDO BACKUP: PERFIL [ ${NOME_PERFIL^^} ]"
echo "=========================================="

# 1. Filtra apenas os diretórios que realmente existem no sistema
ORIGEM_VALIDA=()
for dir in "${ORIGEM_SOLICITADA[@]}"; do
    if [ -d "$dir" ]; then
        ORIGEM_VALIDA+=("$dir")
    else
        log_warn "Diretório ignorado (não encontrado): $dir"
    fi
done

if [ "${#ORIGEM_VALIDA[@]}" -eq 0 ]; then
    alert_webhook "backup_sem_origem" "Perfil '${NOME_PERFIL}': nenhuma das origens configuradas existe neste sistema."
    die "Nenhum dos diretórios especificados para o perfil '$NOME_PERFIL' existe neste sistema."
fi

# 2. Compactação (com exclusão de lixo comum + padrões extras do usuário)
EXCLUDE_PADRAO=(".git" "node_modules" "__pycache__" ".cache")
IFS=',' read -r -a EXCLUDE_EXTRA <<< "${EXCLUDE_PATTERNS:-}"
TAR_EXCLUDE_ARGS=()
for pat in "${EXCLUDE_PADRAO[@]}" "${EXCLUDE_EXTRA[@]}"; do
    [ -n "$pat" ] && TAR_EXCLUDE_ARGS+=(--exclude="$pat")
done

log_info "Diretórios incluídos: ${ORIGEM_VALIDA[*]}"
if [ -n "${EXCLUDE_PATTERNS:-}" ]; then
    log_info "Padrões excluídos: ${EXCLUDE_PADRAO[*]} ${EXCLUDE_EXTRA[*]}"
else
    log_info "Padrões excluídos: ${EXCLUDE_PADRAO[*]}"
fi
log_info "Criando arquivo: $ARQUIVO_FINAL"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    log_info "[DRY-RUN] Nada será criado, enviado ou apagado. Isto é só uma prévia."
    log_info "[DRY-RUN] Tamanho estimado (sem contar exclusões nem compressão):"
    du -sch "${ORIGEM_VALIDA[@]}" 2>/dev/null | tail -n1 | awk '{print "  ~" $1}'
    echo "=========================================="
    exit 0
fi

TAR_ERR_LOG=$(mktemp)
tar -czf "$ARQUIVO_FINAL" "${TAR_EXCLUDE_ARGS[@]}" "${ORIGEM_VALIDA[@]}" 2>"$TAR_ERR_LOG"
TAR_EXIT=$?

# Códigos 0 (sucesso) e 1 (arquivos alterados durante leitura) são válidos
if [ "$TAR_EXIT" -eq 0 ] || [ "$TAR_EXIT" -eq 1 ]; then
    log_ok "Backup criado! Tamanho: $(du -sh "$ARQUIVO_FINAL" | awk '{print $1}')"
else
    rm -f "$ARQUIVO_FINAL"
    # Mostra as primeiras linhas do erro real do tar - antes isso ia pro
    # /dev/null e só sobrava o código numérico, sem pista nenhuma do motivo
    # (achado real testando o painel no ac8 em 2026-10-01: a causa era
    # "Permission denied" em arquivos de /etc por rodar sem root, mas a
    # mensagem original não dava nenhuma dica disso).
    log_error "Saída do tar (primeiras linhas):"
    head -5 "$TAR_ERR_LOG" >&2
    alert_webhook "backup_tar_falhou" "Perfil '${NOME_PERFIL}': tar falhou com código ${TAR_EXIT}."
    rm -f "$TAR_ERR_LOG"
    die "Erro ao criar arquivo de backup (código tar: $TAR_EXIT)."
fi
rm -f "$TAR_ERR_LOG"

# 3. Verificação de integridade: garante que o .tar.gz não está corrompido
# antes de confiar nele, e grava um checksum para detectar corrupção futura
# (bit rot, disco com problema) na hora de restaurar.
log_info "Verificando integridade do backup..."
if ! tar -tzf "$ARQUIVO_FINAL" > /dev/null 2>&1; then
    rm -f "$ARQUIVO_FINAL"
    alert_webhook "backup_corrompido" "Perfil '${NOME_PERFIL}': backup saiu corrompido logo após a criação. Arquivo removido."
    die "Backup corrompido logo após a criação (falha ao listar o conteúdo do .tar.gz). Arquivo removido."
fi

CHECKSUM_FINAL="${ARQUIVO_FINAL}.sha256"
(cd "$DESTINO_FINAL" && sha256sum "$(basename "$ARQUIVO_FINAL")" > "$(basename "$CHECKSUM_FINAL")")
log_ok "Integridade verificada. Checksum: $(basename "$CHECKSUM_FINAL")"

chown -R "${REAL_USER}:${REAL_USER}" "$DESTINO_BASE"

# 4. Envio remoto opcional via rclone (não derruba o backup local em caso de falha)
# RCLONE_REMOTO aceita mais de um destino separados por vírgula, pra redundância
# 3-2-1 real (ex.: um provedor local + um na nuvem) — cada um é independente,
# a falha num não impede o envio pros outros.
if [ -n "${RCLONE_REMOTO:-}" ]; then
    if ! has_cmd rclone; then
        log_warn "RCLONE_REMOTO definido mas rclone não encontrado — envio remoto pulado."
    else
        IFS=',' read -r -a RCLONE_DESTINOS <<< "$RCLONE_REMOTO"
        for remoto in "${RCLONE_DESTINOS[@]}"; do
            [ -n "$remoto" ] || continue
            RCLONE_DESTINO="${remoto%/}/${NOME_PERFIL}/"
            log_info "Enviando backup para remoto: $RCLONE_DESTINO"
            # rclone copy aceita só um arquivo de origem por vez (dest é sempre um diretório aqui)
            # shellcheck disable=SC2086
            if rclone copy "$ARQUIVO_FINAL" "$RCLONE_DESTINO" ${RCLONE_FLAGS:-} 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
                && rclone copy "$CHECKSUM_FINAL" "$RCLONE_DESTINO" ${RCLONE_FLAGS:-} 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
                log_ok "Backup enviado ao remoto: $RCLONE_DESTINO"
            else
                log_warn "Falha ao enviar backup ao remoto ($RCLONE_DESTINO) — backup local preservado."
                alert_webhook "backup_rclone_falhou" "Perfil '${NOME_PERFIL}': falha ao enviar pro remoto ${remoto}."
            fi
        done
    fi
fi

# 5. Rotação de Backups Antigos (específica por perfil)
log_info "Verificando retenção (removendo arquivos com mais de ${RETENCAO_DIAS} dias no perfil ${NOME_PERFIL})..."
find "$DESTINO_FINAL" -maxdepth 1 \( -name "backup_${NOME_PERFIL}_*.tar.gz" -o -name "backup_${NOME_PERFIL}_*.tar.gz.sha256" \) -type f -mtime "+${RETENCAO_DIAS}" -print -delete

echo "------------------------------------------"
echo "📂 Arquivos em $DESTINO_FINAL:"
ls -lh "$DESTINO_FINAL"
echo "=========================================="
