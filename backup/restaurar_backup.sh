#!/bin/bash
# ==============================================================================
# SCRIPT DE RESTAURAÇÃO DE BACKUP MULTI-PERFIL
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_real_user

DESTINO_BASE="${USER_HOME}/backups_sistema"
RETENCAO_PREVENTIVOS_DIAS="${RETENCAO_PREVENTIVOS_DIAS:-30}"

# Mesmo backup.conf do backup_multiperfil.sh, só pra saber onde baixar de volta
# (RCLONE_REMOTO) — não grava nem altera nada lá. Não pré-declara as variáveis:
# load_conf só lê do arquivo quando elas ainda não existem (senão o ambiente teria
# prioridade sobre ele, que é a regra) — usar "${RCLONE_REMOTO:-}" como no
# backup_multiperfil.sh evita erro do "set -u" se nenhuma das duas definir nada.
BACKUP_CONF="${BACKUP_CONF:-${SCRIPT_DIR}/backup.conf}"
load_conf "$BACKUP_CONF" RCLONE_REMOTO RCLONE_FLAGS

echo "=========================================================="
echo " 🔄 ASSISTENTE DE RESTAURAÇÃO DE BACKUP "
echo "=========================================================="

# 0. Origem: backups já locais, ou baixar do remoto configurado primeiro. Só
# oferece a segunda opção se houver RCLONE_REMOTO configurado e rclone instalado
# — senão nem pergunta, pra não confundir quem nunca configurou backup remoto.
ORIGEM="local"
if [ -n "${RCLONE_REMOTO:-}" ] && has_cmd rclone; then
    echo "De onde restaurar?"
    echo "1) Backups locais (${DESTINO_BASE})"
    echo "2) Baixar do remoto configurado antes de restaurar"
    echo "----------------------------------------------------------"
    read -r -p "Escolha [1-2, padrão 1]: " ORIGEM_IDX
    [ "$ORIGEM_IDX" = "2" ] && ORIGEM="remoto"
fi

if [ "$ORIGEM" = "remoto" ]; then
    # RCLONE_REMOTO pode ter mais de um destino (redundância 3-2-1) — pede qual
    # usar quando houver mais de um, só segue direto se houver um único.
    IFS=',' read -r -a RCLONE_DESTINOS <<< "${RCLONE_REMOTO:-}"
    if [ "${#RCLONE_DESTINOS[@]}" -gt 1 ]; then
        echo ""
        echo "Mais de um destino configurado em RCLONE_REMOTO:"
        for i in "${!RCLONE_DESTINOS[@]}"; do
            echo "  $((i+1))) ${RCLONE_DESTINOS[$i]}"
        done
        echo "----------------------------------------------------------"
        read -r -p "Escolha o destino [1-${#RCLONE_DESTINOS[@]}]: " DEST_IDX
        REMOTO_ESCOLHIDO="${RCLONE_DESTINOS[$((DEST_IDX-1))]:-}"
    else
        REMOTO_ESCOLHIDO="${RCLONE_DESTINOS[0]:-}"
    fi
    [ -n "$REMOTO_ESCOLHIDO" ] || die "Destino remoto inválido."
    REMOTO_ESCOLHIDO="${REMOTO_ESCOLHIDO%/}"

    echo ""
    echo "📂 Buscando perfis disponíveis em ${REMOTO_ESCOLHIDO}..."
    mapfile -t PERFIS < <(rclone_usuario lsf "${REMOTO_ESCOLHIDO}/" --dirs-only 2>/dev/null | sed 's#/$##')
    [ "${#PERFIS[@]}" -gt 0 ] || die "Nenhum perfil encontrado em ${REMOTO_ESCOLHIDO} (confira o remote e a conexão com 'rclone lsd ${REMOTO_ESCOLHIDO%%:*}:')."

    for i in "${!PERFIS[@]}"; do
        echo "  $((i+1))) ${PERFIS[$i]}"
    done
    echo "----------------------------------------------------------"
    read -r -p "Escolha o perfil [1-${#PERFIS[@]}]: " PERFIL_IDX

    PERFIL_SELECIONADO="${PERFIS[$((PERFIL_IDX-1))]:-}"
    [ -n "$PERFIL_SELECIONADO" ] || die "Opção de perfil inválida!"

    echo ""
    echo "📂 Buscando backups de [ ${PERFIL_SELECIONADO^^} ] em ${REMOTO_ESCOLHIDO}/${PERFIL_SELECIONADO}/..."
    mapfile -t LINHAS_REMOTO < <(rclone_usuario lsf "${REMOTO_ESCOLHIDO}/${PERFIL_SELECIONADO}/" --files-only \
        --include "backup_${PERFIL_SELECIONADO}_*.tar.gz" --format "pst" --separator ";" 2>/dev/null | sort -t';' -r)
    [ "${#LINHAS_REMOTO[@]}" -gt 0 ] || die "Nenhum backup .tar.gz encontrado em ${REMOTO_ESCOLHIDO}/${PERFIL_SELECIONADO}/."

    NOMES_REMOTO=(); TAMANHOS_REMOTO=(); DATAS_REMOTO=()
    for linha in "${LINHAS_REMOTO[@]}"; do
        NOMES_REMOTO+=("${linha%%;*}")
        resto="${linha#*;}"
        TAMANHOS_REMOTO+=("${resto%%;*}")
        DATAS_REMOTO+=("${resto#*;}")
    done

    echo ""
    echo "Backups disponíveis no remoto (mais recente primeiro):"
    for i in "${!NOMES_REMOTO[@]}"; do
        TAM_H=$(numfmt --to=iec "${TAMANHOS_REMOTO[$i]}" 2>/dev/null || echo "${TAMANHOS_REMOTO[$i]}B")
        echo "  $((i+1))) ${NOMES_REMOTO[$i]} ($TAM_H) - ${DATAS_REMOTO[$i]}"
    done
    echo "----------------------------------------------------------"
    read -r -p "Escolha qual baixar [1-${#NOMES_REMOTO[@]}]: " ARQ_IDX

    ARQ_REMOTO_NOME="${NOMES_REMOTO[$((ARQ_IDX-1))]:-}"
    [ -n "$ARQ_REMOTO_NOME" ] || die "Opção de arquivo inválida!"

    DIR_PERFIL="${DESTINO_BASE}/${PERFIL_SELECIONADO}"
    mkdir -p "$DIR_PERFIL"
    ARQUIVO_SELECIONADO="${DIR_PERFIL}/${ARQ_REMOTO_NOME}"

    if [ -f "$ARQUIVO_SELECIONADO" ]; then
        log_info "Já existe localmente em ${ARQUIVO_SELECIONADO} — usando o que já está baixado, sem baixar de novo."
    else
        echo ""
        log_info "Baixando ${ARQ_REMOTO_NOME} de ${REMOTO_ESCOLHIDO}/${PERFIL_SELECIONADO}/..."
        # shellcheck disable=SC2086
        if ! rclone_usuario copy "${REMOTO_ESCOLHIDO}/${PERFIL_SELECIONADO}/${ARQ_REMOTO_NOME}" "${DIR_PERFIL}/" ${RCLONE_FLAGS:-}; then
            alert_webhook "restauracao_download_falhou" "Perfil '${PERFIL_SELECIONADO}': falha ao baixar ${ARQ_REMOTO_NOME} de ${REMOTO_ESCOLHIDO}."
            die "Falha ao baixar o backup do remoto. Nada foi alterado localmente."
        fi
        # Checksum é melhor esforço: backups antigos podem não ter .sha256 no remoto
        # também — se não existir, a verificação de integridade abaixo cai pro
        # fallback de leitura do tar, igual já faz com backups locais sem checksum.
        # shellcheck disable=SC2086
        rclone_usuario copy "${REMOTO_ESCOLHIDO}/${PERFIL_SELECIONADO}/${ARQ_REMOTO_NOME}.sha256" "${DIR_PERFIL}/" ${RCLONE_FLAGS:-} 2>/dev/null || true
        chown "${REAL_USER}:${REAL_USER}" "$ARQUIVO_SELECIONADO" "${ARQUIVO_SELECIONADO}.sha256" 2>/dev/null || true
        log_ok "Download concluído: $ARQUIVO_SELECIONADO"
    fi
else
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
fi

# 2.1 Verificação de integridade antes de mexer em qualquer coisa: usa o
# checksum gravado na criação do backup se existir (mais confiável — detecta
# corrupção do arquivo mesmo que o tar ainda consiga listá-lo), senão cai
# para um teste de leitura do próprio tar.
echo ""
log_info "Verificando integridade do backup selecionado..."
CHECKSUM_ARQUIVO="${ARQUIVO_SELECIONADO}.sha256"
if [ -f "$CHECKSUM_ARQUIVO" ]; then
    if (cd "$(dirname "$ARQUIVO_SELECIONADO")" && sha256sum -c "$(basename "$CHECKSUM_ARQUIVO")") > /dev/null 2>&1; then
        log_ok "Checksum SHA-256 confere."
    else
        alert_webhook "restauracao_checksum" "Perfil '${PERFIL_SELECIONADO}': checksum não confere em $(basename "$ARQUIVO_SELECIONADO")."
        die "Checksum SHA-256 não confere! O backup pode estar corrompido. Abortando restauração."
    fi
else
    log_warn "Backup sem checksum salvo (criado antes da verificação de integridade). Testando leitura do tar..."
    if ! tar -tzf "$ARQUIVO_SELECIONADO" > /dev/null 2>&1; then
        alert_webhook "restauracao_checksum" "Perfil '${PERFIL_SELECIONADO}': não foi possível ler $(basename "$ARQUIVO_SELECIONADO") (sem checksum salvo)."
        die "Não foi possível ler o conteúdo do backup — arquivo corrompido. Abortando restauração."
    fi
    log_ok "Leitura do tar OK."
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

            # Retenção: preventivos são uma rede de segurança pontual, não um
            # backup permanente — sem isso, cada restauração deixa mais um
            # arquivo em _seguranca_pre_restauracao/ que nunca é removido.
            log_info "Verificando retenção de preventivos (removendo com mais de ${RETENCAO_PREVENTIVOS_DIAS} dias)..."
            find "$SAFETY_DIR" -maxdepth 1 -name "pre_restore_*.tar.gz" -type f \
                -mtime "+${RETENCAO_PREVENTIVOS_DIAS}" -print -delete
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

# 3.1 Verificação de espaço livre: evita começar a extrair e falhar pela metade
# por falta de espaço — especialmente crítico restaurando em / (uma extração
# interrompida no meio pode deixar o sistema num estado pior que antes).
log_info "Verificando espaço livre em $TARGET_DIR antes de extrair..."
TAMANHO_NECESSARIO=$(tar -tvzf "$ARQUIVO_SELECIONADO" 2>/dev/null | awk '{sum+=$3} END{print sum+0}')
ESPACO_LIVRE=$(df -Pk "$TARGET_DIR" 2>/dev/null | awk 'NR==2{print $4*1024}')
if [ -n "$TAMANHO_NECESSARIO" ] && [ -n "$ESPACO_LIVRE" ] && [ "$TAMANHO_NECESSARIO" -gt 0 ] && [ "$ESPACO_LIVRE" -gt 0 ]; then
    if [ "$ESPACO_LIVRE" -lt "$TAMANHO_NECESSARIO" ]; then
        alert_webhook "restauracao_espaco" "Perfil '${PERFIL_SELECIONADO}': espaço insuficiente em ${TARGET_DIR} para restaurar."
        die "Espaço insuficiente em $TARGET_DIR: necessário ~$(numfmt --to=iec "$TAMANHO_NECESSARIO" 2>/dev/null || echo "${TAMANHO_NECESSARIO} bytes"), disponível $(numfmt --to=iec "$ESPACO_LIVRE" 2>/dev/null || echo "${ESPACO_LIVRE} bytes"). Abortando antes de extrair."
    fi
    log_ok "Espaço livre suficiente ($(numfmt --to=iec "$ESPACO_LIVRE" 2>/dev/null || echo "${ESPACO_LIVRE} bytes") disponível, ~$(numfmt --to=iec "$TAMANHO_NECESSARIO" 2>/dev/null || echo "${TAMANHO_NECESSARIO} bytes") necessário)."
else
    log_warn "Não foi possível estimar o espaço necessário/disponível — prosseguindo sem essa verificação."
fi

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
    if [ -n "$SAFETY_TAR" ]; then
        echo "🛟 Backup preventivo do estado anterior: $SAFETY_TAR"
    fi
else
    die "Erro durante a extração do arquivo tar (código: $TAR_EXIT)."
fi
