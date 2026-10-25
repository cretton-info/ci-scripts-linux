#!/usr/bin/env bats
# Testes das funções puras de lib/common.sh — não precisam de root nem alteram
# nada no sistema real. Rodar com: bats tests/

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# --- json_escape ------------------------------------------------------

@test "json_escape: escapa aspas e barra invertida" {
    CI_LOG_DIR="${TEST_TMP}/logs" source "${REPO_ROOT}/lib/common.sh"
    run json_escape 'ele disse "oi" e usou \'
    [ "$status" -eq 0 ]
    [ "$output" = 'ele disse \"oi\" e usou \\' ]
}

@test "json_escape: troca quebra de linha e tab por \\n e \\t" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; json_escape \$'linha1\nlinha2\tcom tab'"
    [ "$status" -eq 0 ]
    [ "$output" = 'linha1\nlinha2\tcom tab' ]
}

@test "json_escape: remove caracteres de controle (ex.: cores ANSI) sem quebrar o JSON" {
    run bash -c "
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        VALOR=\$(printf '\033[90mtexto colorido\033[0m')
        ESCAPADO=\$(json_escape \"\$VALOR\")
        printf '{\"campo\":\"%s\"}' \"\$ESCAPADO\"
    "
    [ "$status" -eq 0 ]
    # o resultado tem que ser JSON válido — sem \033 cru no meio da string
    echo "$output" | jq empty
}

# --- has_cmd -----------------------------------------------------------

@test "has_cmd: retorna sucesso para um comando que existe" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; has_cmd bash"
    [ "$status" -eq 0 ]
}

@test "has_cmd: retorna falha para um comando que não existe" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; has_cmd comando-que-nao-existe-123"
    [ "$status" -ne 0 ]
}

# --- confirm -------------------------------------------------------------

@test "confirm: responder 's' retorna sucesso" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; printf 's\n' | confirm 'pergunta'"
    [ "$status" -eq 0 ]
}

@test "confirm: responder 'S' maiúsculo também retorna sucesso" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; printf 'S\n' | confirm 'pergunta'"
    [ "$status" -eq 0 ]
}

@test "confirm: responder 'n' retorna falha" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; printf 'n\n' | confirm 'pergunta'"
    [ "$status" -ne 0 ]
}

@test "confirm: Enter vazio retorna falha (padrão é não)" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; printf '\n' | confirm 'pergunta'"
    [ "$status" -ne 0 ]
}

# --- detect_real_user ------------------------------------------------------

@test "detect_real_user: usa SUDO_USER quando definido" {
    run bash -c "
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        export SUDO_USER='$(id -un)'
        detect_real_user
        echo \"\$REAL_USER\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$(id -un)" ]
}

@test "detect_real_user: usa o usuário atual quando SUDO_USER não está definido" {
    run bash -c "
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        unset SUDO_USER
        detect_real_user
        echo \"\$REAL_USER\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$(id -un)" ]
}

@test "detect_real_user: CI_REAL_USER tem prioridade sobre SUDO_USER" {
    run bash -c "
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        export SUDO_USER='nao-deve-ser-usado' CI_REAL_USER='$(id -un)'
        detect_real_user
        echo \"\$REAL_USER\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$(id -un)" ]
}

@test "detect_real_user: SUDO_USER=root não conta como usuário real" {
    [ "$EUID" -ne 0 ] || skip "teste pra usuário comum"
    run bash -c "
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        export SUDO_USER=root
        detect_real_user
        echo \"\$REAL_USER\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$(id -un)" ]
}

@test "detect_real_user: root sem sudo (cron) usa o dono do script" {
    [ "$EUID" -eq 0 ] || skip "precisa de root: sudo bats tests/common.bats -f 'root sem sudo'"
    dono=nobody
    cat > "${TEST_TMP}/script.sh" <<EOS
source '${REPO_ROOT}/lib/common.sh'
detect_real_user
echo "\$REAL_USER"
EOS
    chown "$dono" "${TEST_TMP}/script.sh"
    run env -u SUDO_USER USER=root CI_LOG_DIR="${TEST_TMP}/logs" bash "${TEST_TMP}/script.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "$dono" ]
}

@test "detect_real_user: USER_HOME não fica vazio" {
    run bash -c "
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        detect_real_user
        echo \"\$USER_HOME\"
    "
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# --- log_* / die -----------------------------------------------------------

@test "log_info: imprime o prefixo [INFO] e a mensagem" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; log_info 'oi'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"*"oi"* ]]
}

@test "log_ok: imprime o prefixo [ OK ]" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; log_ok 'tudo certo'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ OK ]"*"tudo certo"* ]]
}

@test "log_warn: imprime o prefixo [WARN] e grava em LOG_FILE" {
    run bash -c "
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        log_warn 'cuidado'
        echo \"---\"
        cat \"\$LOG_FILE\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"*"cuidado"* ]]
    [[ "$output" == *"WARN"*"cuidado"* ]]
}

@test "die: sai com código 1 e imprime a mensagem como erro" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; die 'algo deu errado'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[ERRO]"*"algo deu errado"* ]]
}

# --- require_root ------------------------------------------------------

@test "require_root: aborta quando não está rodando como root" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; require_root"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sudo"* ]]
}

# --- alert_webhook ------------------------------------------------------

@test "alert_webhook: não faz nada se WEBHOOK_URL não estiver definida" {
    mkdir -p "${TEST_TMP}/bin"
    CONTADOR="${TEST_TMP}/chamadas_curl"
    : > "$CONTADOR"
    cat > "${TEST_TMP}/bin/curl" <<EOF
#!/bin/bash
echo chamada >> "${CONTADOR}"
EOF
    chmod +x "${TEST_TMP}/bin/curl"

    run bash -c "
        export PATH='${TEST_TMP}/bin:${PATH}'
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        unset WEBHOOK_URL
        alert_webhook 'motivo' 'detalhe'
    "
    [ "$status" -eq 0 ]
    [ ! -s "$CONTADOR" ]
}

@test "alert_webhook: avisa e não trava se curl não existir" {
    run bash -c "
        export PATH='/usr/bin/nao-existe-mesmo'
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        export WEBHOOK_URL='http://exemplo.invalido/'
        alert_webhook 'motivo' 'detalhe'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"curl não encontrado"* ]]
}

@test "alert_webhook: respeita o cooldown (não reenvia o mesmo motivo em seguida)" {
    mkdir -p "${TEST_TMP}/bin"
    CONTADOR="${TEST_TMP}/chamadas_curl"
    : > "$CONTADOR"
    cat > "${TEST_TMP}/bin/curl" <<EOF
#!/bin/bash
echo chamada >> "${CONTADOR}"
exit 0
EOF
    chmod +x "${TEST_TMP}/bin/curl"

    run bash -c "
        export PATH='${TEST_TMP}/bin:${PATH}'
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        export WEBHOOK_URL='http://exemplo.invalido/'
        export ALERTA_COOLDOWN_HORAS=6
        alert_webhook 'motivo_teste' 'primeira'
        alert_webhook 'motivo_teste' 'segunda'
    "
    [ "$status" -eq 0 ]
    CHAMADAS=$(wc -l < "$CONTADOR")
    [ "$CHAMADAS" -eq 1 ]
}

@test "alert_webhook: escapa aspas e barra invertida no payload (JSON válido)" {
    mkdir -p "${TEST_TMP}/bin"
    PAYLOAD_CAPTURADO="${TEST_TMP}/payload.json"
    cat > "${TEST_TMP}/bin/curl" <<'EOF'
#!/bin/bash
for ((i=1; i<=$#; i++)); do
    if [ "${!i}" = "-d" ]; then
        j=$((i+1))
        printf '%s' "${!j}" > "$CI_TEST_PAYLOAD_FILE"
    fi
done
exit 0
EOF
    chmod +x "${TEST_TMP}/bin/curl"

    run bash -c "
        export PATH='${TEST_TMP}/bin:${PATH}'
        export CI_TEST_PAYLOAD_FILE='${PAYLOAD_CAPTURADO}'
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        export WEBHOOK_URL='http://exemplo.invalido/'
        alert_webhook 'motivo_aspas' 'detalhe com \"aspas\" e barra \\ invertida'
    "
    [ "$status" -eq 0 ]
    run jq empty "$PAYLOAD_CAPTURADO"
    [ "$status" -eq 0 ]
}

@test "alert_webhook: motivos diferentes não compartilham cooldown" {
    mkdir -p "${TEST_TMP}/bin"
    CONTADOR="${TEST_TMP}/chamadas_curl"
    : > "$CONTADOR"
    cat > "${TEST_TMP}/bin/curl" <<EOF
#!/bin/bash
echo chamada >> "${CONTADOR}"
exit 0
EOF
    chmod +x "${TEST_TMP}/bin/curl"

    run bash -c "
        export PATH='${TEST_TMP}/bin:${PATH}'
        CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        export WEBHOOK_URL='http://exemplo.invalido/'
        alert_webhook 'motivo_a' 'primeira'
        alert_webhook 'motivo_b' 'segunda'
    "
    [ "$status" -eq 0 ]
    CHAMADAS=$(wc -l < "$CONTADOR")
    [ "$CHAMADAS" -eq 2 ]
}

# --- load_conf --------------------------------------------------------

@test "load_conf: lê só as variáveis permitidas e tira aspas" {
    cat > "${TEST_TMP}/x.conf" <<'CONF'
# comentário
  RCLONE_REMOTO="gdrive:pasta,/media/hd/backups"
EXCLUDE_PATTERNS='# Courses - *'
RETENCAO_DIAS=10
PATH=/tmp/malicioso
CONF
    run bash -c "unset RCLONE_REMOTO EXCLUDE_PATTERNS RETENCAO_DIAS; CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        load_conf '${TEST_TMP}/x.conf' RCLONE_REMOTO EXCLUDE_PATTERNS RETENCAO_DIAS
        printf '%s|%s|%s|%s' \"\$RCLONE_REMOTO\" \"\$EXCLUDE_PATTERNS\" \"\$RETENCAO_DIAS\" \"\$PATH\""
    [ "$status" -eq 0 ]
    [ "${output%|*}" = 'gdrive:pasta,/media/hd/backups|# Courses - *|10' ]
    [ "${output##*|}" != '/tmp/malicioso' ]
}

@test "load_conf: variável do ambiente tem prioridade sobre o arquivo" {
    echo 'RETENCAO_DIAS=10' > "${TEST_TMP}/x.conf"
    run bash -c "RETENCAO_DIAS=3; CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        load_conf '${TEST_TMP}/x.conf' RETENCAO_DIAS; echo \"\$RETENCAO_DIAS\""
    [ "$output" = '3' ]
}

@test "load_conf: não executa o conteúdo do arquivo" {
    printf 'RCLONE_FLAGS=$(touch %s/executou)\n' "${TEST_TMP}" > "${TEST_TMP}/x.conf"
    run bash -c "unset RCLONE_FLAGS; CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        load_conf '${TEST_TMP}/x.conf' RCLONE_FLAGS; echo \"\$RCLONE_FLAGS\""
    [ ! -e "${TEST_TMP}/executou" ]
    [ "$output" = "\$(touch ${TEST_TMP}/executou)" ]
}

@test "load_conf: arquivo inexistente não é erro" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'; load_conf '${TEST_TMP}/nao-existe.conf' X; echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = 'ok' ]
}

# --- marcar_execucao_ok -------------------------------------------------

@test "marcar_execucao_ok: grava um timestamp legível em heartbeats/<nome>.last" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        marcar_execucao_ok 'teste_script'
        cat '${TEST_TMP}/logs/heartbeats/teste_script.last'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "marcar_execucao_ok: chamar de novo atualiza o timestamp (não acumula linhas)" {
    run bash -c "CI_LOG_DIR='${TEST_TMP}/logs' source '${REPO_ROOT}/lib/common.sh'
        marcar_execucao_ok 'teste_script'
        sleep 1
        marcar_execucao_ok 'teste_script'
        wc -l < '${TEST_TMP}/logs/heartbeats/teste_script.last'"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | tr -d ' ')" = '1' ]
}
