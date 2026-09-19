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

chmod +x "$DEST"/*.sh
chown -R "${REAL_USER}:${REAL_USER}" "$DEST"

log_ok "Scripts instalados em $DEST"

if [ "$EUID" -eq 0 ]; then
    read -r -p "Criar atalho global 'painel' em /usr/local/bin? (s/N): " resp
    if [[ "$resp" =~ ^[Ss]$ ]]; then
        ln -sf "$DEST/painel.sh" /usr/local/bin/painel
        log_ok "Atalho criado. Digite 'painel' em qualquer lugar do terminal para abrir o menu."
    fi
else
    log_warn "Rode com sudo para poder criar o atalho global 'painel' em /usr/local/bin."
fi
