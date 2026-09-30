#!/bin/bash
# ==============================================================================
# SCRIPT DE SAÚDE DO SISTEMA (HEALTH CHECK)
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

LIMIAR_DISCO="${LIMIAR_DISCO:-85}"
LIMIAR_MEM="${LIMIAR_MEM:-90}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
ALERTA_COOLDOWN_HORAS="${ALERTA_COOLDOWN_HORAS:-6}"

MODO="texto"
for arg in "$@"; do
    [ "$arg" = "--json" ] && MODO="json"
done

# Junta itens JSON (ex.: objetos de um array) separados por vírgula.
_juntar_json() {
    local IFS=','
    printf '%s' "$*"
}

if [ "$MODO" = "texto" ]; then
    echo "=========================================================="
    echo " 🔍 SAÚDE DO SISTEMA — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================================="
fi

# --- CPU ---------------------------------------------------------------
[ "$MODO" = "texto" ] && echo -e "\n💻 CPU:"
MODELO_CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)
if [ -z "$MODELO_CPU" ] && has_cmd lscpu; then
    MODELO_CPU=$(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)
fi
MODELO_CPU="${MODELO_CPU:-$(uname -m)}"
[ "$MODO" = "texto" ] && echo "  Modelo: ${MODELO_CPU}"

# --- Uptime --------------------------------------------------------------
UPTIME_TXT=$(uptime)
if [ "$MODO" = "texto" ]; then
    echo -e "\n⏱️  Uptime / Carga:"
    echo "$UPTIME_TXT"
fi

# --- Memória -------------------------------------------------------------
if [ "$MODO" = "texto" ]; then
    echo -e "\n💾 Uso de Memória:"
    free -h
fi
# LC_ALL=C força a etiqueta em inglês ("Mem:") — em locales como pt_BR, o
# `free` traduz para "Mem." (com ponto), e o awk abaixo nunca bate com isso,
# fazendo o alerta de memória nunca disparar silenciosamente.
MEM_USO_PCT=$(LC_ALL=C free | awk '/^Mem:/{printf "%.0f", ($3/$2)*100}')
if [ -n "$MEM_USO_PCT" ] && [ "$MEM_USO_PCT" -ge "$LIMIAR_MEM" ] 2>/dev/null; then
    [ "$MODO" = "texto" ] && log_warn "Uso de memória em ${MEM_USO_PCT}% (limiar: ${LIMIAR_MEM}%)"
    alert_webhook "memoria" "${MEM_USO_PCT}% em uso (limiar ${LIMIAR_MEM}%)"
fi

# --- Disco -----------------------------------------------------------------
# Usa < <(...) (não "| while") para o array DISCO_ITENS sobreviver fora do loop.
[ "$MODO" = "texto" ] && echo -e "\n📀 Uso de Disco (partições > ${LIMIAR_DISCO}% em destaque):"
DISCO_ITENS=()
while read -r linha; do
    USO=$(echo "$linha" | awk '{print $5}' | tr -d '%')
    PARTICAO=$(echo "$linha" | awk '{print $1}')
    MONTADO_EM=$(echo "$linha" | awk '{print $NF}')
    ACIMA_LIMIAR="false"
    if [ "$USO" -ge "$LIMIAR_DISCO" ] 2>/dev/null; then
        ACIMA_LIMIAR="true"
        [ "$MODO" = "texto" ] && echo "  🔴 $linha"
        alert_webhook "disco_${MONTADO_EM}" "${PARTICAO} em ${MONTADO_EM} com ${USO}% (limiar ${LIMIAR_DISCO}%)"
    else
        [ "$MODO" = "texto" ] && echo "     $linha"
    fi
    if [ "$MODO" = "json" ]; then
        DISCO_ITENS+=("{\"particao\":\"$(json_escape "$PARTICAO")\",\"montado_em\":\"$(json_escape "$MONTADO_EM")\",\"uso_pct\":${USO:-0},\"acima_limiar\":${ACIMA_LIMIAR}}")
    fi
done < <(df -hP --exclude-type=tmpfs --exclude-type=devtmpfs | tail -n +2)

# --- Top processos -----------------------------------------------------
if [ "$MODO" = "texto" ]; then
    echo -e "\n🧠 Top 5 processos por uso de CPU:"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6
    echo -e "\n📊 Top 5 processos por uso de RAM:"
    ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 6
fi
TOP_CPU_ITENS=()
TOP_MEM_ITENS=()
if [ "$MODO" = "json" ]; then
    while read -r pid comm cpu mem; do
        [ -n "$pid" ] || continue
        TOP_CPU_ITENS+=("{\"pid\":${pid},\"comando\":\"$(json_escape "$comm")\",\"cpu_pct\":${cpu:-0},\"mem_pct\":${mem:-0}}")
    done < <(ps -eo pid,comm,%cpu,%mem --sort=-%cpu --no-headers | head -n 5)

    while read -r pid comm cpu mem; do
        [ -n "$pid" ] || continue
        TOP_MEM_ITENS+=("{\"pid\":${pid},\"comando\":\"$(json_escape "$comm")\",\"cpu_pct\":${cpu:-0},\"mem_pct\":${mem:-0}}")
    done < <(ps -eo pid,comm,%cpu,%mem --sort=-%mem --no-headers | head -n 5)
fi

# --- Conectividade -----------------------------------------------------
INTERNET_OK="false"
DNS_OK="false"
ping -c 2 -W 2 1.1.1.1 &>/dev/null && INTERNET_OK="true"
ping -c 2 -W 2 google.com &>/dev/null && DNS_OK="true"
if [ "$MODO" = "texto" ]; then
    echo -e "\n🌐 Conectividade de Rede:"
    if [ "$INTERNET_OK" = "true" ]; then log_ok "Conexão com a internet (IP): OK"; else log_warn "Conexão com a internet (IP): FALHA"; fi
    if [ "$DNS_OK" = "true" ]; then log_ok "Resolução DNS: OK"; else log_warn "Resolução DNS: FALHA"; fi
fi

# --- Serviços systemd falhando ------------------------------------------
SERVICOS_FALHANDO_ITENS=()
if has_cmd systemctl; then
    FALHAS=$(systemctl list-units --state=failed --no-legend 2>/dev/null)
    if [ -n "$FALHAS" ]; then
        if [ "$MODO" = "texto" ]; then
            echo -e "\n🛠️  Serviços systemd falhando:"
            echo "$FALHAS"
        fi
        alert_webhook "servicos_systemd" "$(echo "$FALHAS" | wc -l) serviço(s) em estado de falha"
        if [ "$MODO" = "json" ]; then
            # Primeiro campo é o marcador visual (●), o nome da unidade é o segundo.
            while read -r _ nome _; do
                [ -n "$nome" ] && SERVICOS_FALHANDO_ITENS+=("\"$(json_escape "$nome")\"")
            done <<< "$FALHAS"
        fi
    elif [ "$MODO" = "texto" ]; then
        echo -e "\n🛠️  Serviços systemd falhando:"
        log_ok "Nenhum serviço em estado de falha."
    fi
fi

# --- Docker --------------------------------------------------------------
DOCKER_ITENS=()
if has_cmd docker; then
    if [ "$MODO" = "texto" ]; then
        echo -e "\n🐳 Contêineres Docker:"
        docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || log_warn "Não foi possível consultar o Docker (permissão?)."
    else
        while IFS=$'\t' read -r nome status imagem; do
            [ -n "$nome" ] && DOCKER_ITENS+=("{\"nome\":\"$(json_escape "$nome")\",\"status\":\"$(json_escape "$status")\",\"imagem\":\"$(json_escape "$imagem")\"}")
        done < <(docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null)
    fi
fi

if [ "$MODO" = "texto" ]; then
    echo -e "\n=========================================================="
else
    printf '{'
    printf '"hostname":"%s",' "$(json_escape "$(hostname)")"
    printf '"data":"%s",' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '"cpu_modelo":"%s",' "$(json_escape "$MODELO_CPU")"
    printf '"uptime":"%s",' "$(json_escape "$UPTIME_TXT")"
    printf '"memoria_uso_pct":%s,' "${MEM_USO_PCT:-null}"
    printf '"disco":[%s],' "$(_juntar_json "${DISCO_ITENS[@]}")"
    printf '"top_cpu":[%s],' "$(_juntar_json "${TOP_CPU_ITENS[@]}")"
    printf '"top_mem":[%s],' "$(_juntar_json "${TOP_MEM_ITENS[@]}")"
    printf '"conectividade":{"internet":%s,"dns":%s},' "$INTERNET_OK" "$DNS_OK"
    printf '"servicos_falhando":[%s],' "$(_juntar_json "${SERVICOS_FALHANDO_ITENS[@]}")"
    printf '"docker_containers":[%s]' "$(_juntar_json "${DOCKER_ITENS[@]}")"
    printf '}\n'
fi
