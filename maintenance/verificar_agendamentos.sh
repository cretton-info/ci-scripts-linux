#!/bin/bash
# ==============================================================================
# VERIFICA SE OS AGENDAMENTOS (BACKUP, ATUALIZAÇÃO, SIMULADO) AINDA ESTÃO RODANDO
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
# Por que este script existe: backup_multiperfil.sh, atualizar_sistema.sh e
# simulado_restauracao.sh só alertam via WEBHOOK_URL quando FALHAM — se o cron
# parar de chamá-los (crontab apagado numa reinstalação, disco cheio, permissão
# quebrada), nada roda e por isso nada alerta. Este script verifica por fora,
# comparando a data do último heartbeat de sucesso de cada um com um limite
# esperado, e alerta se algum estiver atrasado ou nunca tiver rodado.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

exibir_ajuda() {
    cat <<EOF
Uso: sudo $0

Verifica se backup_multiperfil.sh (por perfil), atualizar_sistema.sh e
simulado_restauracao.sh ainda estão sendo chamados pelo cron, comparando a
data do último heartbeat de sucesso de cada um com um limite esperado. Só
avalia o que encontra configurado (perfil de backup com pelo menos uma
execução, script referenciado em algum crontab) — não é preciso ter os três
pra usar este script. Alerta via WEBHOOK_URL se algo estiver atrasado ou
nunca tiver rodado com sucesso apesar de agendado. Seguro pra rodar via cron
(ex.: diariamente), sem efeito colateral — só leitura.

Variáveis de ambiente:
  AGENDAMENTO_MAX_HORAS_BACKUP      Horas sem um novo backup bem-sucedido por
                                     perfil até alertar (padrão: 48 — ajuste se
                                     seu backup for semanal, não diário).
  AGENDAMENTO_MAX_HORAS_SIMULADO    Horas sem o simulado de restauração rodar
                                     com sucesso até alertar (padrão: 192 = 8
                                     dias, pra um agendamento semanal com
                                     margem).
  WEBHOOK_URL                       Se definida, alerta quando algo abaixo do
                                     esperado é encontrado.

atualizar_sistema.sh não tem variável própria: o limite é estimado a partir
da própria linha de cron criada pelo "atualizar_sistema.sh --agendar" (diária
ou semanal), com margem.
EOF
}

for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
        exibir_ajuda
        exit 0
    fi
done

require_root
detect_real_user

AGENDAMENTO_MAX_HORAS_BACKUP="${AGENDAMENTO_MAX_HORAS_BACKUP:-48}"
AGENDAMENTO_MAX_HORAS_SIMULADO="${AGENDAMENTO_MAX_HORAS_SIMULADO:-192}"
MARCADOR_CRON_ATUALIZACAO="ci-scripts-linux:atualizar_sistema"

echo "=========================================================="
echo " ⏱️  VERIFICAÇÃO DE AGENDAMENTOS — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="

PROBLEMAS=0

# Procura o heartbeat de um script tanto no local padrão de root (se o cron
# dele estiver no crontab do root, convenção deste repositório para scripts
# que exigem sudo) quanto no do usuário real (scripts sem exigência de root
# podem estar no crontab do próprio usuário) — usa o mais recente dos dois.
heartbeat_mais_recente() {
    local nome="$1" melhor_ts=0 candidato ts
    for candidato in \
        "/var/log/ci-scripts-linux/heartbeats/${nome}.last" \
        "${USER_HOME}/.local/state/ci-scripts-linux/logs/heartbeats/${nome}.last"
    do
        [ -f "$candidato" ] || continue
        ts=$(cat "$candidato" 2>/dev/null || echo 0)
        [[ "$ts" =~ ^[0-9]+$ ]] || continue
        [ "$ts" -gt "$melhor_ts" ] && melhor_ts="$ts"
    done
    echo "$melhor_ts"
}

verificar_heartbeat() {
    local nome="$1" max_horas="$2" motivo_alerta="$3" descricao="$4"
    local hb_ts agora idade_h
    hb_ts=$(heartbeat_mais_recente "$nome")
    agora=$(date +%s)
    if [ "$hb_ts" -eq 0 ]; then
        PROBLEMAS=$((PROBLEMAS + 1))
        log_error "${descricao}: agendado, mas nunca terminou com sucesso (sem heartbeat registrado)."
        alert_webhook "$motivo_alerta" "${descricao}: agendado mas nenhuma execução bem-sucedida registrada ainda."
        return
    fi
    idade_h=$(( (agora - hb_ts) / 3600 ))
    if [ "$idade_h" -gt "$max_horas" ]; then
        PROBLEMAS=$((PROBLEMAS + 1))
        log_error "${descricao}: última execução bem-sucedida há ${idade_h}h (limite: ${max_horas}h) — o cron pode ter parado de rodar."
        alert_webhook "$motivo_alerta" "${descricao}: última execução há ${idade_h}h (limite ${max_horas}h)."
    else
        log_ok "${descricao}: última execução bem-sucedida há ${idade_h}h (dentro do limite de ${max_horas}h)."
    fi
}

# --- 1. Backups (um check por perfil que já tiver pelo menos um backup) ---
echo ""
echo "── Backups (backup_multiperfil.sh) ──────────────────────"
DESTINO_BASE="${USER_HOME}/backups_sistema"
if [ -d "$DESTINO_BASE" ]; then
    ENCONTROU_PERFIL=0
    while IFS= read -r -d '' perfil_dir; do
        perfil=$(basename "$perfil_dir")
        [ "$perfil" = "_seguranca_pre_restauracao" ] && continue
        ls "${perfil_dir}"/backup_"${perfil}"_*.tar.gz >/dev/null 2>&1 || continue
        ENCONTROU_PERFIL=1
        verificar_heartbeat "backup_${perfil}" "$AGENDAMENTO_MAX_HORAS_BACKUP" \
            "agendamento_backup_${perfil}" "Backup do perfil '${perfil}'"
    done < <(find "$DESTINO_BASE" -mindepth 1 -maxdepth 1 -type d -print0)
    [ "$ENCONTROU_PERFIL" -eq 1 ] || log_info "Nenhum perfil com backup encontrado em ${DESTINO_BASE} ainda — nada a verificar."
else
    log_info "Diretório de backups (${DESTINO_BASE}) não existe ainda — nada a verificar."
fi

# --- 2. atualizar_sistema.sh (limite estimado a partir do próprio cron) ---
echo ""
echo "── Atualização automática (atualizar_sistema.sh) ────────"
LINHA_CRON_ATUALIZACAO=$(crontab -l 2>/dev/null | grep "$MARCADOR_CRON_ATUALIZACAO" || true)
if [ -n "$LINHA_CRON_ATUALIZACAO" ]; then
    read -r _min _hora _dia_mes _mes dia_semana _resto <<< "$LINHA_CRON_ATUALIZACAO"
    if [ "$dia_semana" = "*" ]; then
        MAX_H_ATUALIZACAO=36   # diária: 24h + margem
    else
        MAX_H_ATUALIZACAO=218  # semanal: 7 dias + margem
    fi
    verificar_heartbeat "atualizar_sistema" "$MAX_H_ATUALIZACAO" \
        "agendamento_atualizacao" "Atualização automática do sistema"
else
    log_info "atualizar_sistema.sh não está agendado no crontab do root — nada a verificar (use '--agendar' pra configurar)."
fi

# --- 3. simulado_restauracao.sh (não exige root, pode estar em qualquer crontab) ---
echo ""
echo "── Simulado de restauração (simulado_restauracao.sh) ─────"
TEM_CRON_SIMULADO=0
crontab -l 2>/dev/null | grep -q "simulado_restauracao.sh" && TEM_CRON_SIMULADO=1
if [ "$TEM_CRON_SIMULADO" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
    crontab -u "$REAL_USER" -l 2>/dev/null | grep -q "simulado_restauracao.sh" && TEM_CRON_SIMULADO=1
fi
if [ "$TEM_CRON_SIMULADO" -eq 1 ]; then
    verificar_heartbeat "simulado_restauracao" "$AGENDAMENTO_MAX_HORAS_SIMULADO" \
        "agendamento_simulado" "Simulado de restauração"
else
    log_info "simulado_restauracao.sh não encontrado em nenhum crontab — nada a verificar."
fi

echo ""
echo "=========================================================="
if [ "$PROBLEMAS" -eq 0 ]; then
    log_ok "Nenhum agendamento atrasado."
else
    log_error "${PROBLEMAS} agendamento(s) atrasado(s) ou nunca executado(s) — ver acima."
fi
echo "=========================================================="

[ "$PROBLEMAS" -eq 0 ]
