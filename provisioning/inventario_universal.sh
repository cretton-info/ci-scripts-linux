#!/bin/bash
# ==============================================================================
# SCRIPT DE INVENTÁRIO COMPLETO DE HARDWARE & OS
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

detect_real_user

# Resolucao do destino dos relatorios, em ordem de prioridade:
# 1. Variavel de ambiente DIR_DESTINO (override pontual, ex: rodar manual)
# 2. Arquivo inventario.conf ao lado do script (gravado pelo install.sh na
#    instalacao, pergunta interativa uma unica vez por host)
# 3. Padrao ~/inventario, se nada acima existir
INVENTARIO_CONF="${SCRIPT_DIR}/inventario.conf"
if [ -z "${DIR_DESTINO:-}" ] && [ -f "$INVENTARIO_CONF" ]; then
    # shellcheck source=/dev/null
    source "$INVENTARIO_CONF"
fi
DIR_DESTINO="${DIR_DESTINO:-${USER_HOME}/inventario}"
mkdir -p "$DIR_DESTINO"

MODO="texto"
for arg in "$@"; do
    [ "$arg" = "--json" ] && MODO="json"
done

_juntar_json() {
    local IFS=','
    printf '%s' "$*"
}

# ------------------------------------------------------------------
# 1. Coleta: Sistema e Hardware
# ------------------------------------------------------------------
if [ -f /etc/os-release ]; then
    OS_NAME=$(. /etc/os-release; echo "${PRETTY_NAME:-desconhecido}")
else
    OS_NAME="desconhecido"
fi
KERNEL=$(uname -r)
ARCH=$(uname -m)

MODELO_FULL=""
MOTHERBOARD=""
BIOS_VER=""
if [ "$EUID" -eq 0 ] && has_cmd dmidecode; then
    MODELO_FULL=$(dmidecode -s system-product-name 2>/dev/null)
    MOTHERBOARD=$(dmidecode -s baseboard-product-name 2>/dev/null)
    BIOS_VER=$(dmidecode -s bios-version 2>/dev/null)
else
    log_warn "Rode com sudo para detectar modelo da máquina, placa-mãe, BIOS e slots de RAM (via dmidecode)."
fi
[ -z "$MODELO_FULL" ] && MODELO_FULL="$(hostname)"
[ -z "$MOTHERBOARD" ] && MOTHERBOARD="Não identificada (requer sudo)"
[ -z "$BIOS_VER" ] && BIOS_VER="Não identificada (requer sudo)"

MODELO_NOME=$(echo "$MODELO_FULL" | awk '{print $1}' | tr -cd '[:alnum:]_')
[ -z "$MODELO_NOME" ] && MODELO_NOME="maquina"

FILE_HARDWARE="${DIR_DESTINO}/hardware_${MODELO_NOME}.md"
FILE_SOFTWARE="${DIR_DESTINO}/software_${MODELO_NOME}.md"
DATE_NOW=$(date '+%Y-%m-%d %H:%M')

# LC_ALL=C força a etiqueta em inglês ("Model name") — em locales como pt_BR,
# o lscpu traduz para "Nome do modelo" e o grep abaixo nunca bate, deixando o
# campo de CPU sempre vazio.
if has_cmd lscpu; then
    CPU_INFO=$(LC_ALL=C lscpu | grep -m1 'Model name' | cut -d':' -f2 | xargs)
else
    CPU_INFO=$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)
fi
CPU_CORES=$(nproc 2>/dev/null || echo "N/A")

MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_INFO=$(awk "BEGIN {printf \"%.2f GB\", $MEM_KB/1024/1024}")

GPU_INFO=$(lspci 2>/dev/null | grep -i 'vga\|3d' | cut -d':' -f3 | xargs)
[ -z "$GPU_INFO" ] && GPU_INFO="Não detectada"

# `paste -sd ", " -` intercalaria "," e " " como separadores alternados (não
# ", " fixo) — junta com "," e normaliza pro separador certo com sed.
DISKS_LIST=$(lsblk -d -o NAME,SIZE,MODEL,TYPE 2>/dev/null | grep disk | awk '{
    if (NF >= 4) print $1" ("$2" - "$3")"; else print $1" ("$2")"
}' | paste -sd ',' - | sed 's/,/, /g')
[ -z "$DISKS_LIST" ] && DISKS_LIST="Não detectados"
STORAGE_USAGE=$(df -h / 2>/dev/null | tail -n1 | awk '{print $3" usado de "$2" (livre: "$4")"}')

NET_INTERFACES=$(ip -br addr show 2>/dev/null | grep -v '^lo' | awk '{print $1" ("$3")"}' | paste -sd ',' - | sed 's/,/, /g')
MAC_ADDRS=$(ip link show 2>/dev/null | grep -i ether | awk '{print $2}' | paste -sd ',' - | sed 's/,/, /g')

# Slots de memória (dmidecode -t 17): total, ocupados/livres e módulo por módulo.
SLOTS_RESUMO="Requer sudo para detectar (dmidecode)."
SLOTS_DETALHE=""
TOTAL_SLOTS=""
SLOTS_LIVRES=""
SLOTS_OCUPADOS=""
if [ "$EUID" -eq 0 ] && has_cmd dmidecode; then
    DMI_MEM=$(dmidecode -t 17 2>/dev/null)
    if [ -n "$DMI_MEM" ] && echo "$DMI_MEM" | grep -q '^Memory Device$'; then
        TOTAL_SLOTS=$(echo "$DMI_MEM" | grep -c '^Memory Device$')
        SLOTS_LIVRES=$(echo "$DMI_MEM" | grep -c 'Size: No Module Installed')
        SLOTS_OCUPADOS=$((TOTAL_SLOTS - SLOTS_LIVRES))
        SLOTS_RESUMO="${SLOTS_OCUPADOS}/${TOTAL_SLOTS} slots ocupados (${SLOTS_LIVRES} livres)"
        SLOTS_DETALHE=$(echo "$DMI_MEM" | awk -F': ' '
            /^Memory Device$/ { if (locator != "") print "  " locator ": " size; locator=""; size="" }
            /^\tSize/         { size=$2 }
            /^\tLocator/ && $0 !~ /Bank Locator/ { locator=$2 }
            END { if (locator != "") print "  " locator ": " size }
        ')
    else
        SLOTS_RESUMO="dmidecode não retornou dados (comum em VMs sem BIOS/firmware completo)."
    fi
fi

# ------------------------------------------------------------------
# 2. Coleta: Software, apps e serviços
# ------------------------------------------------------------------
UFW_STATUS="Não instalado"
if has_cmd ufw; then
    if [ "$EUID" -eq 0 ]; then
        UFW_STATUS=$(ufw status 2>/dev/null | grep -q "^Status: active" && echo "Ativo" || echo "Inativo")
    else
        UFW_STATUS="Instalado (rode com sudo para ver o status)"
    fi
fi
TAILSCALE_STATUS=$(has_cmd tailscale && echo "Instalado" || echo "Não instalado")

DOCKER_VER=$(has_cmd docker && docker --version 2>/dev/null || echo "Não instalado")
COMPOSE_VER="Não instalado"
has_cmd docker && COMPOSE_VER=$(docker compose version 2>/dev/null | head -n1)
[ -z "$COMPOSE_VER" ] && COMPOSE_VER="Não instalado"
GIT_VER=$(git --version 2>/dev/null || echo "Não instalado")
PYTHON_VER=$(python3 --version 2>/dev/null || echo "Não instalado")
NODE_VER=$(node -v 2>/dev/null || echo "Não instalado")
NPM_VER=$(npm -v 2>/dev/null || echo "Não instalado")
OLLAMA_STATUS=$(has_cmd ollama && echo "Instalado" || echo "Não instalado")

# Verifica um app por comando no PATH (com versão, se possível), pacote apt,
# flatpak, snap ou atalho .desktop — cobre as formas mais comuns de instalação.
detectar_app() {
    local termo="$1"; shift
    local cmd
    for cmd in "$@"; do
        if has_cmd "$cmd"; then
            local ver
            # </dev/null evita que apps que leem stdin (ex.: obsidian --version,
            # via snap) consumam o stdin do loop "while read < apps.conf" lá
            # embaixo, o que travava a detecção depois do primeiro app da lista.
            # timeout evita travar o script inteiro caso algum app não trate
            # "--version" direito e abra a janela normal em vez de responder e sair
            # (aconteceu de verdade com Obsidian e Antigravity durante os testes).
            ver=$(timeout 3 "$cmd" --version </dev/null 2>/dev/null | head -n1)
            if [ -n "$ver" ]; then
                echo "$ver"
            else
                echo "sim (comando '$cmd')"
            fi
            return
        fi
    done
    if has_cmd dpkg && dpkg -l 2>/dev/null | grep -qi "$termo"; then
        echo "sim (pacote apt)"
        return
    fi
    if has_cmd flatpak && flatpak list 2>/dev/null | grep -qi "$termo"; then
        echo "sim (flatpak)"
        return
    fi
    if has_cmd snap && snap list 2>/dev/null | grep -qi "$termo"; then
        echo "sim (snap)"
        return
    fi
    if find /usr/share/applications "${USER_HOME}/.local/share/applications" -maxdepth 1 \
            -iname "*${termo}*.desktop" 2>/dev/null | grep -q .; then
        echo "sim (atalho .desktop)"
        return
    fi
    echo "não encontrado"
}

APPS_CONF="${APPS_CONF:-${SCRIPT_DIR}/apps.conf}"
APPS_NOMES=()
APPS_RESULTADOS=()
if [ -f "$APPS_CONF" ]; then
    while IFS='|' read -r nome termo comandos; do
        [[ -z "$nome" || "$nome" =~ ^[[:space:]]*# ]] && continue
        IFS=',' read -r -a cmds <<< "$comandos"
        APPS_NOMES+=("$nome")
        APPS_RESULTADOS+=("$(detectar_app "$termo" "${cmds[@]}")")
    done < "$APPS_CONF"
else
    log_warn "apps.conf não encontrado em $APPS_CONF, usando lista padrão embutida."
    for par in "Obsidian|obsidian|obsidian" "VS Code|code|code,code-insiders" \
               "Antigravity|antigravity|antigravity" "Wine|wine|wine,wine64"; do
        IFS='|' read -r nome termo comandos <<< "$par"
        IFS=',' read -r -a cmds <<< "$comandos"
        APPS_NOMES+=("$nome")
        APPS_RESULTADOS+=("$(detectar_app "$termo" "${cmds[@]}")")
    done
fi

if [ "$MODO" = "texto" ]; then
    # ------------------------------------------------------------------
    # 3. Exibição no terminal
    # ------------------------------------------------------------------
    echo "=========================================================="
    echo " 📊 INVENTÁRIO DE HARDWARE & SISTEMA OPERACIONAL "
    echo "=========================================================="

    echo -e "\n🖥️  Sistema:"
    echo "  Hostname: $(hostname)"
    echo "  Modelo: $MODELO_FULL"
    echo "  SO: $OS_NAME"
    echo "  Kernel: $KERNEL"
    echo "  Arquitetura: $ARCH"

    echo -e "\n🔩 CPU:"
    echo "  $CPU_INFO ($CPU_CORES núcleos)"

    echo -e "\n💾 Memória:"
    free -h
    echo -e "\n🧠 Slots de Memória (RAM): $SLOTS_RESUMO"
    [ -n "$SLOTS_DETALHE" ] && echo "$SLOTS_DETALHE"

    echo -e "\n📀 Discos e Partições:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null || df -h

    echo -e "\n🌐 Interfaces de Rede:"
    ip -brief addr show 2>/dev/null

    echo -e "\n📦 Pacotes / Runtimes relevantes:"
    printf "  %s\n" "$DOCKER_VER" "$COMPOSE_VER" "$GIT_VER" "$PYTHON_VER" "$NODE_VER"

    echo -e "\n🖊️  Aplicativos Desktop:"
    for i in "${!APPS_NOMES[@]}"; do
        printf "  %-15s %s\n" "${APPS_NOMES[$i]}:" "${APPS_RESULTADOS[$i]}"
    done

    echo -e "\n=========================================================="

    # ------------------------------------------------------------------
    # 4. Geração dos relatórios em Markdown (~/inventario/)
    # ------------------------------------------------------------------
    mkdir -p "$DIR_DESTINO"
    cat << DOC > "$FILE_HARDWARE"
# 💻 Especificações de Hardware — $MODELO_FULL

## 🛠️ Componentes Principais
| Componente | Especificação Detalhada |
| :--- | :--- |
| **Modelo da Máquina** | $MODELO_FULL |
| **Placa Mãe** | $MOTHERBOARD |
| **Processador (CPU)** | $CPU_INFO ($CPU_CORES núcleos) |
| **Memória RAM** | $RAM_INFO |
| **Slots de Memória** | $SLOTS_RESUMO |
| **Placa de Vídeo (GPU)** | $GPU_INFO |
| **Firmware / BIOS** | $BIOS_VER |

## 💾 Armazenamento
| Item | Detalhes |
| :--- | :--- |
| **Discos Detectados** | $DISKS_LIST |
| **Uso da Partição Raiz (/)** | $STORAGE_USAGE |

## 🌐 Rede & Conectividade
| Recurso | Detalhes |
| :--- | :--- |
| **Interfaces & IP** | $NET_INTERFACES |
| **Endereço MAC** | $MAC_ADDRS |

---
*Gerado por: $REAL_USER em $DATE_NOW*
DOC

    {
        cat << DOC
# 🐧 Inventário de Software & Serviços — $MODELO_FULL

## ⚙️ Sistema Operacional & Base
| Item | Detalhe / Status |
| :--- | :--- |
| **Sistema Operacional** | $OS_NAME |
| **Kernel Linux** | $KERNEL |
| **Arquitetura** | $ARCH |
| **Firewall (UFW)** | $UFW_STATUS |
| **Tailscale** | $TAILSCALE_STATUS |

---

## 🖊️ Aplicativos Desktop
| Aplicação | Status / Versão |
| :--- | :--- |
DOC
        for i in "${!APPS_NOMES[@]}"; do
            printf "| **%s** | %s |\n" "${APPS_NOMES[$i]}" "${APPS_RESULTADOS[$i]}"
        done
        cat << DOC

---

## 🛠️ Ambientes de Desenvolvimento
| Ferramenta | Status / Versão |
| :--- | :--- |
| **Node.js** | $NODE_VER |
| **NPM** | $NPM_VER |
| **Python 3** | $PYTHON_VER |
| **Git** | $GIT_VER |

---

## 🐳 Containers & Home Lab
| Serviço | Status de Execução |
| :--- | :--- |
| **Docker Engine** | $DOCKER_VER |
| **Docker Compose** | $COMPOSE_VER |
| **Ollama (IA Local)** | $OLLAMA_STATUS |

---
*Gerado por: $REAL_USER em $DATE_NOW*
DOC
    } > "$FILE_SOFTWARE"

    chown -R "${REAL_USER}:${REAL_USER}" "$DIR_DESTINO" 2>/dev/null || true

    log_ok "Relatórios salvos em: $DIR_DESTINO"
    ls -lh "$DIR_DESTINO"
else
    # ------------------------------------------------------------------
    # 3'. Saída em JSON — não escreve nada em disco, só imprime pra stdout.
    # ------------------------------------------------------------------
    DISCOS_ITENS=()
    while read -r nome tamanho modelo tipo; do
        [ "$tipo" = "disk" ] || continue
        DISCOS_ITENS+=("{\"nome\":\"$(json_escape "$nome")\",\"tamanho\":\"$(json_escape "$tamanho")\",\"modelo\":\"$(json_escape "${modelo:-}")\"}")
    done < <(lsblk -d -o NAME,SIZE,MODEL,TYPE 2>/dev/null | tail -n +2)

    INTERFACES_ITENS=()
    while read -r nome ip_cidr; do
        [ -n "$nome" ] || continue
        INTERFACES_ITENS+=("{\"nome\":\"$(json_escape "$nome")\",\"ip\":\"$(json_escape "${ip_cidr:-}")\"}")
    done < <(ip -br addr show 2>/dev/null | grep -v '^lo' | awk '{print $1, $3}')

    MACS_ITENS=()
    while read -r mac; do
        [ -n "$mac" ] && MACS_ITENS+=("\"$(json_escape "$mac")\"")
    done < <(ip link show 2>/dev/null | grep -i ether | awk '{print $2}')

    APPS_ITENS=()
    for i in "${!APPS_NOMES[@]}"; do
        APPS_ITENS+=("{\"nome\":\"$(json_escape "${APPS_NOMES[$i]}")\",\"status\":\"$(json_escape "${APPS_RESULTADOS[$i]}")\"}")
    done

    NUCLEOS_JSON="null"
    [[ "$CPU_CORES" =~ ^[0-9]+$ ]] && NUCLEOS_JSON="$CPU_CORES"
    SLOTS_TOTAL_JSON="${TOTAL_SLOTS:-null}"
    SLOTS_LIVRES_JSON="${SLOTS_LIVRES:-null}"
    SLOTS_OCUPADOS_JSON="${SLOTS_OCUPADOS:-null}"

    printf '{'
    printf '"hostname":"%s",' "$(json_escape "$(hostname)")"
    printf '"modelo":"%s",' "$(json_escape "$MODELO_FULL")"
    printf '"placa_mae":"%s",' "$(json_escape "$MOTHERBOARD")"
    printf '"bios":"%s",' "$(json_escape "$BIOS_VER")"
    printf '"so":"%s",' "$(json_escape "$OS_NAME")"
    printf '"kernel":"%s",' "$(json_escape "$KERNEL")"
    printf '"arquitetura":"%s",' "$(json_escape "$ARCH")"
    printf '"cpu":{"modelo":"%s","nucleos":%s},' "$(json_escape "$CPU_INFO")" "$NUCLEOS_JSON"
    printf '"memoria":{"total":"%s","slots_total":%s,"slots_livres":%s,"slots_ocupados":%s},' \
        "$(json_escape "$RAM_INFO")" "$SLOTS_TOTAL_JSON" "$SLOTS_LIVRES_JSON" "$SLOTS_OCUPADOS_JSON"
    printf '"gpu":"%s",' "$(json_escape "$GPU_INFO")"
    printf '"discos":[%s],' "$(_juntar_json "${DISCOS_ITENS[@]}")"
    printf '"armazenamento_raiz":"%s",' "$(json_escape "${STORAGE_USAGE:-}")"
    printf '"interfaces_rede":[%s],' "$(_juntar_json "${INTERFACES_ITENS[@]}")"
    printf '"enderecos_mac":[%s],' "$(_juntar_json "${MACS_ITENS[@]}")"
    printf '"ufw":"%s",' "$(json_escape "$UFW_STATUS")"
    printf '"tailscale":"%s",' "$(json_escape "$TAILSCALE_STATUS")"
    printf '"ollama":"%s",' "$(json_escape "$OLLAMA_STATUS")"
    printf '"runtimes":{"docker":"%s","docker_compose":"%s","git":"%s","python3":"%s","node":"%s","npm":"%s"},' \
        "$(json_escape "$DOCKER_VER")" "$(json_escape "$COMPOSE_VER")" "$(json_escape "$GIT_VER")" \
        "$(json_escape "$PYTHON_VER")" "$(json_escape "$NODE_VER")" "$(json_escape "$NPM_VER")"
    printf '"apps_desktop":[%s]' "$(_juntar_json "${APPS_ITENS[@]}")"
    printf '}\n'
fi
