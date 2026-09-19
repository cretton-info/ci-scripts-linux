#!/bin/bash
# ==============================================================================
# SCRIPT DE INVENTÁRIO COMPLETO DE HARDWARE & OS
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

echo "=========================================================="
echo " 📊 INVENTÁRIO DE HARDWARE & SISTEMA OPERACIONAL "
echo "=========================================================="

echo -e "\n🖥️  Sistema:"
echo "  Hostname: $(hostname)"
if [ -f /etc/os-release ]; then
    (. /etc/os-release; echo "  SO: ${PRETTY_NAME:-desconhecido}")
fi
echo "  Kernel: $(uname -r)"
echo "  Arquitetura: $(uname -m)"

echo -e "\n🔩 CPU:"
if has_cmd lscpu; then
    lscpu | grep -E 'Model name|Socket|Core|Thread'
else
    grep -m1 'model name' /proc/cpuinfo
fi

echo -e "\n💾 Memória:"
free -h

echo -e "\n🧠 Slots de Memória (RAM):"
if has_cmd dmidecode; then
    if [ "$EUID" -eq 0 ]; then
        DMI_MEM=$(dmidecode -t 17 2>/dev/null)
        if [ -n "$DMI_MEM" ] && echo "$DMI_MEM" | grep -q '^Memory Device$'; then
            TOTAL_SLOTS=$(echo "$DMI_MEM" | grep -c '^Memory Device$')
            SLOTS_LIVRES=$(echo "$DMI_MEM" | grep -c 'Size: No Module Installed')
            SLOTS_OCUPADOS=$((TOTAL_SLOTS - SLOTS_LIVRES))
            echo "$DMI_MEM" | awk -F': ' '
                /^Memory Device$/ { if (locator != "") print "  " locator ": " size; locator=""; size="" }
                /^\tSize/         { size=$2 }
                /^\tLocator/ && $0 !~ /Bank Locator/ { locator=$2 }
                END { if (locator != "") print "  " locator ": " size }
            '
            echo "  Total: ${SLOTS_OCUPADOS}/${TOTAL_SLOTS} slots ocupados (${SLOTS_LIVRES} livres)"
        else
            log_warn "dmidecode não retornou dados de memória (comum em VMs sem BIOS/firmware completo)."
        fi
    else
        log_warn "Rode com sudo para ver os slots de memória (dmidecode precisa de root)."
    fi
else
    log_warn "dmidecode não encontrado — não é possível detectar slots de memória."
fi

echo -e "\n📀 Discos e Partições:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null || df -h

echo -e "\n🌐 Interfaces de Rede:"
ip -brief addr show 2>/dev/null

echo -e "\n📦 Pacotes / Runtimes relevantes:"
for pkg_cmd in "docker --version" "docker compose version" "git --version" "python3 --version" "node --version"; do
    if has_cmd "${pkg_cmd%% *}"; then
        printf "  %s\n" "$($pkg_cmd 2>/dev/null | head -n1)"
    fi
done

# Verifica um app por comando no PATH, pacote apt, flatpak, snap ou atalho
# .desktop — cobre as formas mais comuns de instalação em desktop Linux.
detectar_app() {
    local termo="$1"; shift
    local cmd
    for cmd in "$@"; do
        if has_cmd "$cmd"; then
            echo "sim (comando '$cmd')"
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
    if find /usr/share/applications "${HOME}/.local/share/applications" -maxdepth 1 \
            -iname "*${termo}*.desktop" 2>/dev/null | grep -q .; then
        echo "sim (atalho .desktop)"
        return
    fi
    echo "não encontrado"
}

echo -e "\n🖊️  Aplicativos Desktop:"
printf "  %-13s %s\n" "Obsidian:" "$(detectar_app obsidian obsidian)"
printf "  %-13s %s\n" "VS Code:" "$(detectar_app code code code-insiders)"
printf "  %-13s %s\n" "Antigravity:" "$(detectar_app antigravity antigravity)"
printf "  %-13s %s\n" "Wine:" "$(detectar_app wine wine wine64)"

echo -e "\n=========================================================="
