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

exibir_ajuda() {
    cat <<EOF
Uso: sudo $0 [PERFIL]

Opções de Perfil de Backup:
  1, docs      Arquivos do Usuário e Documentos (~/Documentos + /etc)
  2, homelab   Dumps de Banco / Home Lab / Web (/var/www + /opt/docker-containers + /etc)
  3, scripts   Projetos de Automação e Scripts (~/scripts + /etc)
  4, tudo      Backup Completo (todas as origens acima)
  --menu       Exibe o menu interativo para seleção

Variáveis de ambiente:
  RETENCAO_DIAS  Dias de retenção dos backups antigos (padrão: 7)
EOF
}

MODO="${1:-}"

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

DESTINO_FINAL="${DESTINO_BASE}/${NOME_PERFIL}"
mkdir -p "$DESTINO_FINAL"
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
    die "Nenhum dos diretórios especificados para o perfil '$NOME_PERFIL' existe neste sistema."
fi

# 2. Compactação
log_info "Diretórios incluídos: ${ORIGEM_VALIDA[*]}"
log_info "Criando arquivo: $ARQUIVO_FINAL"

tar -czf "$ARQUIVO_FINAL" "${ORIGEM_VALIDA[@]}" 2>/dev/null
TAR_EXIT=$?

# Códigos 0 (sucesso) e 1 (arquivos alterados durante leitura) são válidos
if [ "$TAR_EXIT" -eq 0 ] || [ "$TAR_EXIT" -eq 1 ]; then
    log_ok "Backup criado! Tamanho: $(du -sh "$ARQUIVO_FINAL" | awk '{print $1}')"
else
    rm -f "$ARQUIVO_FINAL"
    die "Erro ao criar arquivo de backup (código tar: $TAR_EXIT)."
fi

# 3. Verificação de integridade: garante que o .tar.gz não está corrompido
# antes de confiar nele, e grava um checksum para detectar corrupção futura
# (bit rot, disco com problema) na hora de restaurar.
log_info "Verificando integridade do backup..."
if ! tar -tzf "$ARQUIVO_FINAL" > /dev/null 2>&1; then
    rm -f "$ARQUIVO_FINAL"
    die "Backup corrompido logo após a criação (falha ao listar o conteúdo do .tar.gz). Arquivo removido."
fi

CHECKSUM_FINAL="${ARQUIVO_FINAL}.sha256"
(cd "$DESTINO_FINAL" && sha256sum "$(basename "$ARQUIVO_FINAL")" > "$(basename "$CHECKSUM_FINAL")")
log_ok "Integridade verificada. Checksum: $(basename "$CHECKSUM_FINAL")"

chown -R "${REAL_USER}:${REAL_USER}" "$DESTINO_BASE"

# 4. Rotação de Backups Antigos (específica por perfil)
log_info "Verificando retenção (removendo arquivos com mais de ${RETENCAO_DIAS} dias no perfil ${NOME_PERFIL})..."
find "$DESTINO_FINAL" -maxdepth 1 \( -name "backup_${NOME_PERFIL}_*.tar.gz" -o -name "backup_${NOME_PERFIL}_*.tar.gz.sha256" \) -type f -mtime "+${RETENCAO_DIAS}" -print -delete

echo "------------------------------------------"
echo "📂 Arquivos em $DESTINO_FINAL:"
ls -lh "$DESTINO_FINAL"
echo "=========================================="
