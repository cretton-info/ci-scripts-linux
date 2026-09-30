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
