#!/bin/bash
# ==============================================================================
# INSTALADOR — copia os scripts do repositório para ~/scripts (flat),
# preservando a compatibilidade com o painel.sh e crontabs existentes.
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/lib/common.sh"

detect_real_user
DEST="${USER_HOME}/scripts"

log_info "Instalando scripts em: $DEST"
mkdir -p "$DEST/lib"

cp -v "${SCRIPT_DIR}/lib/common.sh" "$DEST/lib/"

for dir in backup monitoring provisioning maintenance panel; do
    for f in "${SCRIPT_DIR}/${dir}"/*.sh; do
        [ -e "$f" ] || continue
        cp -v "$f" "$DEST/"
    done
    # Arquivos de configuração (ex.: apps.conf) só são copiados se ainda não
    # existirem no destino, para não sobrescrever customizações do usuário
    # numa reinstalação.
    for f in "${SCRIPT_DIR}/${dir}"/*.conf; do
        [ -e "$f" ] || continue
        dest_f="$DEST/$(basename "$f")"
        if [ -e "$dest_f" ]; then
            log_info "Mantendo $(basename "$f") existente em $DEST (edite manualmente se quiser atualizar)."
        else
            cp -v "$f" "$DEST/"
        fi
    done
done

# Versão instalada: usa a tag/commit do git se o SCRIPT_DIR for um checkout git
# (ex.: "v1.0.0" ou "v1.0.0-3-gabc1234" se houver commits depois da tag); cai
# pra "desconhecida" se não for um checkout git (ex.: baixado como zip).
if [ -d "${SCRIPT_DIR}/.git" ] && has_cmd git; then
    VERSAO=$(cd "$SCRIPT_DIR" && git describe --tags --always --dirty 2>/dev/null)
fi
echo "${VERSAO:-desconhecida}" > "$DEST/VERSION"

chmod +x "$DEST"/*.sh
chown -R "${REAL_USER}:${REAL_USER}" "$DEST"

log_ok "Scripts instalados em $DEST (versão: ${VERSAO:-desconhecida})"

# Pergunta a pasta de destino do inventario_universal.sh uma unica vez por
# host (nao sobrescreve numa reinstalacao, mesma logica do apps.conf acima).
# So pergunta em terminal interativo, pra nao travar instalacao automatizada.
INVENTARIO_CONF="$DEST/inventario.conf"
if [ -e "$INVENTARIO_CONF" ]; then
    log_info "Mantendo inventario.conf existente em $DEST (edite manualmente se quiser mudar a pasta de destino)."
elif [ -t 0 ]; then
    DEFAULT_INVENTARIO_DIR="${USER_HOME}/inventario"
    read -r -p "Pasta de destino dos relatorios de inventario [${DEFAULT_INVENTARIO_DIR}]: " resp_dir
    INVENTARIO_DIR="${resp_dir:-$DEFAULT_INVENTARIO_DIR}"
    printf 'DIR_DESTINO="%s"\n' "$INVENTARIO_DIR" > "$INVENTARIO_CONF"
    chown "${REAL_USER}:${REAL_USER}" "$INVENTARIO_CONF"
    log_ok "Pasta de destino do inventario salva em $INVENTARIO_CONF: $INVENTARIO_DIR"
else
    log_warn "Instalacao nao-interativa: inventario.conf nao criado, inventario_universal.sh vai usar o padrao (~/inventario) ate ser configurado manualmente."
fi

if [ "$EUID" -eq 0 ]; then
    read -r -p "Criar atalho global 'painel' em /usr/local/bin? (s/N): " resp
    if [[ "$resp" =~ ^[Ss]$ ]]; then
        ln -sf "$DEST/painel.sh" /usr/local/bin/painel
        log_ok "Atalho criado. Digite 'painel' em qualquer lugar do terminal para abrir o menu."
    fi

    # Rotação dos logs automáticos: só instala se ainda não existir, para não
    # sobrescrever uma customização feita depois da instalação.
    if [ -d /etc/logrotate.d ]; then
        if [ -e /etc/logrotate.d/ci-scripts-linux ]; then
            log_info "Mantendo /etc/logrotate.d/ci-scripts-linux existente (edite manualmente se quiser atualizar)."
        else
            cp -v "${SCRIPT_DIR}/lib/logrotate.conf" /etc/logrotate.d/ci-scripts-linux
            log_ok "Rotação de logs instalada em /etc/logrotate.d/ci-scripts-linux."
        fi
    fi
else
    log_warn "Rode com sudo para poder criar o atalho global 'painel' e instalar a rotação de logs."
fi
