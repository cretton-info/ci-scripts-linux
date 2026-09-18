#!/bin/bash
# ==============================================================================
# SCRIPT DE RESTAURAÇÃO DE BACKUP MULTI-PERFIL
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_real_user

DESTINO_BASE="${USER_HOME}/backups_sistema"

echo "=========================================================="
echo " 🔄 ASSISTENTE DE RESTAURAÇÃO DE BACKUP "
echo "=========================================================="

[ -d "$DESTINO_BASE" ] || die "Diretório de backups não encontrado em: $DESTINO_BASE"

# 1. Seleção do Perfil
echo "Selecione o perfil de backup para restaurar:"
PERFIS=()
while IFS= read -r -d '' d; do
    PERFIS+=("$(basename "$d")")
done < <(find "$DESTINO_BASE" -mindepth 1 -maxdepth 1 -type d -print0)

[ "${#PERFIS[@]}" -gt 0 ] || die "Nenhum perfil de backup encontrado dentro de $DESTINO_BASE."

for i in "${!PERFIS[@]}"; do
    echo "  $((i+1))) ${PERFIS[$i]}"
done
echo "----------------------------------------------------------"
read -r -p "Escolha o perfil [1-${#PERFIS[@]}]: " PERFIL_IDX

PERFIL_SELECIONADO="${PERFIS[$((PERFIL_IDX-1))]:-}"
[ -n "$PERFIL_SELECIONADO" ] || die "Opção de perfil inválida!"

DIR_PERFIL="${DESTINO_BASE}/${PERFIL_SELECIONADO}"

# 2. Seleção do Arquivo .tar.gz (mais recente primeiro)
echo ""
echo "📂 Buscando arquivos de backup no perfil [ ${PERFIL_SELECIONADO^^} ]..."
ARQUIVOS=()
while IFS= read -r -d '' f; do
    ARQUIVOS+=("$f")
done < <(find "$DIR_PERFIL" -maxdepth 1 -name "backup_${PERFIL_SELECIONADO}_*.tar.gz" -type f -printf '%T@ %p\0' \
            | sort -z -rn | sed -z 's/^[^ ]* //')

[ "${#ARQUIVOS[@]}" -gt 0 ] || die "Nenhum arquivo de backup .tar.gz encontrado em $DIR_PERFIL."

echo ""
echo "Backups disponíveis (do mais recente ao mais antigo):"
for i in "${!ARQUIVOS[@]}"; do
    ARQ_NAME=$(basename "${ARQUIVOS[$i]}")
    ARQ_SIZE=$(du -sh "${ARQUIVOS[$i]}" | awk '{print $1}')
    ARQ_DATE=$(stat -c %y "${ARQUIVOS[$i]}" | cut -d'.' -f1)
    echo "  $((i+1))) $ARQ_NAME ($ARQ_SIZE) - $ARQ_DATE"
done
echo "----------------------------------------------------------"
read -r -p "Escolha qual arquivo restaurar [1-${#ARQUIVOS[@]}]: " ARQ_IDX

ARQUIVO_SELECIONADO="${ARQUIVOS[$((ARQ_IDX-1))]:-}"
if [ -z "$ARQUIVO_SELECIONADO" ] || [ ! -f "$ARQUIVO_SELECIONADO" ]; then
    die "Opção de arquivo inválida!"
fi

# 3. Definição do Local de Destino
echo ""
echo "=========================================================="
echo " 🎯 DESTINO DA RESTAURAÇÃO"
echo "=========================================================="
echo "1) Restaurar nos LOCAIS ORIGINAIS (sobrescreve os arquivos existentes no sistema!)"
echo "2) Restaurar em um DIRETÓRIO TEMPORÁRIO (seguro para auditoria/conferência)"
echo "----------------------------------------------------------"
read -r -p "Escolha o modo de restauração [1-2]: " MODO_DESTINO

SAFETY_TAR=""

case "$MODO_DESTINO" in
    1)
        TARGET_DIR="/"
        echo ""
        echo "⚠️  ATENÇÃO CRÍTICA: os arquivos extraídos irão SOBRESCREVER o sistema raiz (/)."
        echo "Antes de prosseguir, listando o conteúdo do backup para conferência (primeiros 20 itens):"
        tar -tzf "$ARQUIVO_SELECIONADO" | head -n 20
        echo ""
        confirm "Tem certeza absoluta que deseja continuar?" || { log_warn "Operação cancelada pelo usuário."; exit 0; }

        # Rede de segurança: salva o estado atual dos caminhos que serão sobrescritos
        # antes de restaurar, para permitir reverter caso algo dê errado.
        SAFETY_DIR="${DESTINO_BASE}/_seguranca_pre_restauracao"
        mkdir -p "$SAFETY_DIR"
        SAFETY_TAR="${SAFETY_DIR}/pre_restore_${PERFIL_SELECIONADO}_$(date +%Y%m%d_%H%M%S).tar.gz"

        # Usa as raízes reais gravadas no backup (ex.: "etc/", "root/scripts/"),
        # não só o primeiro componente do caminho — senão um perfil que inclui
        # ~/scripts (root/scripts/...) faria o preventivo copiar o /root INTEIRO
        # (incluindo backups anteriores dentro dele, crescendo a cada execução).
        mapfile -t TODOS_DIRS < <(tar -tzf "$ARQUIVO_SELECIONADO" | grep '/$')
        RAIZES=()
        for d in "${TODOS_DIRS[@]}"; do
            aninhado=0
            for outro in "${TODOS_DIRS[@]}"; do
                [ "$d" = "$outro" ] && continue
                case "$d" in
                    "$outro"*) aninhado=1; break ;;
                esac
            done
            [ "$aninhado" -eq 0 ] && RAIZES+=("${d%/}")
        done

        CAMINHOS_EXISTENTES=()
        for r in "${RAIZES[@]}"; do
            [ -e "/$r" ] && CAMINHOS_EXISTENTES+=("$r")
        done

        if [ "${#CAMINHOS_EXISTENTES[@]}" -gt 0 ]; then
            log_info "Criando backup preventivo do estado atual em: $SAFETY_TAR"
            # --exclude é defesa extra: mesmo com as raízes já filtradas acima,
            # nunca deixa o preventivo engolir a si mesmo (backups_sistema).
            tar -czf "$SAFETY_TAR" --exclude="${DESTINO_BASE#/}" -C / "${CAMINHOS_EXISTENTES[@]}" 2>/dev/null || true
            log_ok "Backup preventivo salvo. Em caso de problema, restaure-o manualmente com: tar -xzf $SAFETY_TAR -C /"
        fi
        ;;
    2)
        TARGET_DIR="${USER_HOME}/restauracao_temp_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$TARGET_DIR"
        echo ""
        echo "📁 Os arquivos serão extraídos em: $TARGET_DIR"
        ;;
    *)
        die "Opção de destino inválida!"
        ;;
esac

# 4. Execução da Restauração
echo ""
echo "📦 Extraindo $(basename "$ARQUIVO_SELECIONADO")..."
tar -xzf "$ARQUIVO_SELECIONADO" -C "$TARGET_DIR" 2>/dev/null
TAR_EXIT=$?

if [ "$TAR_EXIT" -eq 0 ]; then
    if [ "$TARGET_DIR" != "/" ]; then
        chown -R "${REAL_USER}:${REAL_USER}" "$TARGET_DIR"
    fi
    echo ""
    echo "=========================================="
    log_ok "RESTAURAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "=========================================="
    echo "📍 Arquivos restaurados em: $TARGET_DIR"
    [ -n "$SAFETY_TAR" ] && echo "🛟 Backup preventivo do estado anterior: $SAFETY_TAR"
else
    die "Erro durante a extração do arquivo tar (código: $TAR_EXIT)."
fi
