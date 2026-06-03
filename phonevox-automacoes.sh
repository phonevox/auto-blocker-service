#!/usr/bin/env bash
# phonevox-automacoes.sh — Gerenciador de automações Phonevox

CONFIG_DIR="/etc/phonevox/automacoes"
KEY_FILE="$CONFIG_DIR/crypted_key"
CONFIG_FILE="$CONFIG_DIR/config"
LAST_RESPONSE_FILE="$CONFIG_DIR/last_response"
LOG_FILE="/var/log/phonevox-automacoes.log"
URL_CONFIG="$CONFIG_DIR/urls"
LOCK_FILE="/tmp/phonevox-automacoes.lock"
DRY_RUN="${DRY_RUN:-0}"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { 
    rotate_logs
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

rotate_logs() {
    local max_size=$((10 * 1024 * 1024))
    
    if [[ -f "$LOG_FILE" ]]; then
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
        
        if [[ $size -gt $max_size ]]; then
            local timestamp=$(date '+%Y%m%d-%H%M%S')
            mv "$LOG_FILE" "${LOG_FILE}.${timestamp}"
            gzip "${LOG_FILE}.${timestamp}" 2>/dev/null || true
            touch "$LOG_FILE"
            chmod 600 "$LOG_FILE"
        fi
    fi
}

die() { printf '%b\n' "${RED}[ERRO]${NC} $*" >&2; exit 1; }
require_root() { [[ $EUID -ne 0 ]] && die "Execute como root."; }
init_dirs() { mkdir -p "$CONFIG_DIR"; chmod 700 "$CONFIG_DIR"; touch "$LOG_FILE"; chmod 600 "$LOG_FILE"; }

validate_type() { [[ "$1" =~ ^(opa|pabx|did)$ ]] || die "Tipo inválido: '$1'"; }
validate_code() { [[ -n "$1" && ${#1} -le 255 ]] || die "Code inválido"; }

acquire_lock() {
    local timeout=30
    local elapsed=0
    while [[ -f "$LOCK_FILE" ]] && [[ $elapsed -lt $timeout ]]; do
        sleep 1
        ((elapsed++))
    done
    touch "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

find_pm2() {
    local pm2_paths=(
        "$(command -v pm2 2>/dev/null)"
        "/usr/local/bin/pm2"
        "/usr/bin/pm2"
        "$HOME/.npm/_npx/*/bin/pm2"
        "$HOME/.nvm/versions/node/*/bin/pm2"
    )
    
    for path in "${pm2_paths[@]}"; do
        [[ -x "$path" ]] && echo "$path" && return 0
    done
    
    return 1
}

load_urls() {
    [[ -f "$URL_CONFIG" ]] && source "$URL_CONFIG" || die "URLs não configuradas. Execute: install"
}

execute_command() {
    local cmd="$1"
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Seria executado: $cmd"
    else
        if eval "$cmd"; then
            log "Comando executado com sucesso: $cmd"
        else
            log "ERRO ao executar: $cmd"
        fi
    fi
}

generate_register_curl() {
    local type="$1" code="$2"
    log "Gerando comando curl para registro (type=$type)..."
    
    local curl_cmd="curl -L -X POST \"${API_REGISTER}\" -H \"Content-Type: application/json\" -d '{\"type\":\"${type}\",\"code\":\"${code}\"}'"
    echo "$curl_cmd"
}

execute_status_check() {
    acquire_lock
    trap release_lock EXIT
    
    load_urls
    source "$CONFIG_FILE"
    
    local crypted_key encoded_key last_status
    crypted_key=$(cat "$KEY_FILE")
    encoded_key=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$crypted_key'))")
    
    if [[ -f "$LAST_RESPONSE_FILE" ]]; then
        last_status=$(grep "^HTTP_STATUS=" "$LAST_RESPONSE_FILE" | cut -d= -f2)
        last_status="${last_status:-000}"
    else
        last_status="000"
    fi

    log "Consultando status (type=$TYPE, last_status=$last_status)..."
    
    local http_code
    http_code=$(curl -sL --max-time 30 -o /dev/null -w "%{http_code}" \
        "${API_STATUS}?type=${TYPE}&crypted_key=${encoded_key}&last_status=${last_status}")

    printf 'HTTP_STATUS=%s\nTIMESTAMP="%s"\n' "$http_code" "$(date '+%Y-%m-%d %H:%M:%S')" > "$LAST_RESPONSE_FILE"
    chmod 600 "$LAST_RESPONSE_FILE"
    log "HTTP Status: $http_code"

    case "$http_code" in
        200) 
            if [[ "$last_status" == "200" ]]; then
                log "Status 200 (sem mudança, nenhuma ação)"
            else
                local pm2_bin
                pm2_bin=$(find_pm2)
                if [[ -n "$pm2_bin" ]]; then
                    log "Ação: pm2 restart all"
                    execute_command "\"$pm2_bin\" restart all >> \"$LOG_FILE\" 2>&1"
                else
                    log "AVISO: pm2 não encontrado em nenhum caminho"
                fi
            fi
            ;;
        402) 
            local pm2_bin
            pm2_bin=$(find_pm2)
            if [[ -n "$pm2_bin" ]]; then
                log "Ação: pm2 stop all"
                execute_command "\"$pm2_bin\" stop all >> \"$LOG_FILE\" 2>&1"
            else
                log "AVISO: pm2 não encontrado em nenhum caminho"
            fi
            ;;
        *) log "Status $http_code ignorado" ;;
    esac
}

save_key_config() {
    printf '%s' "$3" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    printf 'TYPE=%s\nCODE=%s\n' "$1" "$2" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    log "Key e config salvos"
}

install_service() {
    local script_path="$0"
    
    if [[ ! "$script_path" =~ ^/ ]]; then
        script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    fi
    
    if [[ ! -f "$script_path" ]]; then
        die "Não foi possível encontrar o script em: $script_path"
    fi
    
    cp -f "$script_path" /usr/local/sbin/phonevox-automacoes
    chmod 755 /usr/local/sbin/phonevox-automacoes

    cat > /etc/systemd/system/phonevox-automacoes.service <<'EOF'
[Unit]
Description=Phonevox Automacoes Runner
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/phonevox-automacoes run
User=root
StandardOutput=append:/var/log/phonevox-automacoes.log
StandardError=append:/var/log/phonevox-automacoes.log
EOF

    cat > /etc/systemd/system/phonevox-automacoes.timer <<'EOF'
[Unit]
Description=Phonevox Automacoes
Requires=phonevox-automacoes.service

[Timer]
OnCalendar=*:0/10
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now phonevox-automacoes.timer
    log "Service + timer instalados"
}

cmd_install() {
    require_root
    init_dirs

    printf '%b\n' "${CYAN}═══════════════════════════════════════${NC}"
    printf '%b\n' "${BOLD}  Instalação - Phonevox Automações${NC}"
    printf '%b\n' "${CYAN}═══════════════════════════════════════${NC}"
    printf '\n'
    
    read -rp "$(printf '%b' "${BLUE}URL Base${NC}") (ex: https://auto-blocker.falevox.com.br): " URL_BASE
    [[ -z "$URL_BASE" ]] && die "URL_BASE vazio"
    [[ "$URL_BASE" != https://* ]] && URL_BASE="https://${URL_BASE}"
    
    printf 'URL_BASE="%s"\nAPI_REGISTER="${URL_BASE}/register"\nAPI_STATUS="${URL_BASE}"\n' "$URL_BASE" > "$URL_CONFIG"
    chmod 600 "$URL_CONFIG"

    printf '%b\n' "\nTipos disponíveis: ${YELLOW}opa${NC}, ${YELLOW}pabx${NC}, ${YELLOW}did${NC}"
    read -rp "$(printf '%b' "${BLUE}Type${NC}"): " TYPE
    validate_type "$TYPE"
    
    read -rp "$(printf '%b' "${BLUE}Code${NC}") (máx 255): " CODE
    validate_code "$CODE"

    load_urls
    printf '%b\n' "\n${RED}╔═════════════════════════════════════════════════════╗${NC}"
    printf '%b\n' "${RED}║ ⚠️  IMPORTANTE - REDE PERMITIDA OBRIGATÓRIA         ║${NC}"
    printf '%b\n' "${RED}╠═════════════════════════════════════════════════════╣${NC}"
    printf '%b\n' "${RED}║ Este comando DEVE ser executado APENAS em uma      ║${NC}"
    printf '%b\n' "${RED}║ máquina conectada à rede permitida (VPN/Interna)   ║${NC}"
    printf '%b\n' "${RED}║ Não execute em rede pública ou sem autorização!    ║${NC}"
    printf '%b\n' "${RED}╚═════════════════════════════════════════════════════╝${NC}\n"
    printf '%b\n' "${GREEN}▶ Copie e execute no Windows/seu sistema:${NC}\n"
    CURL_CMD=$(generate_register_curl "$TYPE" "$CODE")
    printf '%b\n' "${BOLD}${YELLOW}${CURL_CMD}${NC}\n"
    
    read -rsp "$(printf '%b' "${CYAN}Cole aqui o crypted_key recebido${NC}"): " CRYPTED_KEY
    printf '\n'
    [[ -z "$CRYPTED_KEY" ]] && die "crypted_key vazio"
    
    save_key_config "$TYPE" "$CODE" "$CRYPTED_KEY"
    install_service
    printf '%b\n' "${GREEN}✓ Instalação OK${NC}"
    
    printf '\n%b\n' "${BLUE}Executando verificação inicial de status...${NC}"
    execute_status_check
}

cmd_reconfig() {
    require_root
    load_urls

    printf '%b\n' "${CYAN}═══════════════════════════════════════${NC}"
    printf '%b\n' "${BOLD}  Reconfiguração - Phonevox Automações${NC}"
    printf '%b\n' "${CYAN}═══════════════════════════════════════${NC}\n"

    printf '%b\n' "Tipos disponíveis: ${YELLOW}opa${NC}, ${YELLOW}pabx${NC}, ${YELLOW}did${NC}"
    read -rp "$(printf '%b' "${BLUE}Type${NC}"): " TYPE
    validate_type "$TYPE"
    
    read -rp "$(printf '%b' "${BLUE}Code${NC}") (máx 255): " CODE
    validate_code "$CODE"

    load_urls
    printf '%b\n' "\n${RED}╔═════════════════════════════════════════════════════╗${NC}"
    printf '%b\n' "${RED}║ ⚠️  IMPORTANTE - REDE PERMITIDA OBRIGATÓRIA         ║${NC}"
    printf '%b\n' "${RED}╠═════════════════════════════════════════════════════╣${NC}"
    printf '%b\n' "${RED}║ Este comando DEVE ser executado APENAS em uma      ║${NC}"
    printf '%b\n' "${RED}║ máquina conectada à rede permitida (VPN/Interna)   ║${NC}"
    printf '%b\n' "${RED}║ Não execute em rede pública ou sem autorização!    ║${NC}"
    printf '%b\n' "${RED}╚═════════════════════════════════════════════════════╝${NC}\n"
    printf '%b\n' "${GREEN}▶ Copie e execute no Windows/seu sistema:${NC}\n"
    CURL_CMD=$(generate_register_curl "$TYPE" "$CODE")
    printf '%b\n' "${BOLD}${YELLOW}${CURL_CMD}${NC}\n"
    
    read -rsp "$(printf '%b' "${CYAN}Cole aqui o crypted_key recebido${NC}"): " CRYPTED_KEY
    printf '\n'
    [[ -z "$CRYPTED_KEY" ]] && die "crypted_key vazio"
    
    save_key_config "$TYPE" "$CODE" "$CRYPTED_KEY"
    printf '%b\n' "${GREEN}✓ Reconfiguração OK${NC}"
    
    printf '\n%b\n' "${BLUE}Executando verificação de status...${NC}"
    execute_status_check
}

cmd_run() {
    require_root
    [[ -f "$KEY_FILE" && -f "$CONFIG_FILE" ]] || die "Config não encontrada. Execute: install"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log "========== MODO DRY-RUN ATIVADO =========="
    fi
    
    execute_status_check
}

cmd_status() {
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}"
    printf '%b\n' "${BOLD}  Phonevox Automações — Status${NC}"
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}\n"
    
    if [[ -f "$URL_CONFIG" ]]; then
        printf '%b\n' "${BLUE}--- URLs ---${NC}"
        cat "$URL_CONFIG"
    else
        printf '%b\n' "${YELLOW}URLs: não configuradas${NC}"
    fi
    printf '\n'
    
    if [[ -f "$CONFIG_FILE" ]]; then
        printf '%b\n' "${BLUE}--- Config ---${NC}"
        cat "$CONFIG_FILE"
    else
        printf '%b\n' "${YELLOW}Config: não encontrada${NC}"
    fi
    printf '\n'
    
    if [[ -f "$KEY_FILE" ]]; then
        printf '%b\n' "${BLUE}--- Key ---${NC}"
        cut -c1-20 "$KEY_FILE"; printf "...\n"
    else
        printf '%b\n' "${YELLOW}Key: não encontrada${NC}"
    fi
    printf '\n'
    
    if [[ -f "$LAST_RESPONSE_FILE" ]]; then
        printf '%b\n' "${BLUE}--- Última Resposta ---${NC}"
        cat "$LAST_RESPONSE_FILE"
    else
        printf '%b\n' "${YELLOW}Last Response: nenhuma${NC}"
    fi
    printf '\n'
    
    printf '%b\n' "${BLUE}--- Timer ---${NC}"
    systemctl list-timers phonevox-automacoes.timer --no-pager 2>/dev/null || printf "Timer não instalado\n"
    printf '\n'
    
    printf '%b\n' "${BLUE}--- Log (últimas 20 linhas) ---${NC}"
    tail -n 20 "$LOG_FILE" 2>/dev/null || printf "Log vazio\n"
}

cmd_start() {
    require_root
    log "Iniciando service + timer..."
    systemctl enable --now phonevox-automacoes.timer
    log "Service iniciado"
    printf '%b\n' "${GREEN}✓ Service iniciado${NC}"
}

cmd_stop() {
    require_root
    log "Parando service + timer..."
    systemctl stop phonevox-automacoes.timer
    systemctl stop phonevox-automacoes.service
    systemctl disable phonevox-automacoes.timer
    log "Service parado e desabilitado"
    printf '%b\n' "${GREEN}✓ Service parado${NC}"
}

cmd_help() {
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}"
    printf '%b\n' "${BOLD}  Phonevox Automações${NC}"
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}\n"
    printf '%b\n' "${BOLD}Uso:${NC} phonevox-automacoes [opção] [flag]\n"
    printf '%b\n' "${BOLD}Opções:${NC}"
    printf '%b\n' "  ${YELLOW}--install${NC}   Configura URL base, type/code, gera curl e instala service"
    printf '%b\n' "  ${YELLOW}--reconfig${NC}  Regenera nova key"
    printf '%b\n' "  ${YELLOW}--run${NC}       Executa verificação de status"
    printf '%b\n' "  ${YELLOW}--status${NC}    Exibe config completa"
    printf '%b\n' "  ${YELLOW}--logs${NC}      Exibe últimas 100 linhas do log"
    printf '%b\n' "  ${YELLOW}--update${NC}    Faz git pull e atualiza script"
    printf '%b\n' "  ${YELLOW}--start${NC}     Inicia o service e timer"
    printf '%b\n' "  ${YELLOW}--stop${NC}      Para o service e timer"
    printf '%b\n' "  ${YELLOW}--help${NC}      Este menu\n"
    printf '%b\n' "${BOLD}Flags:${NC}"
    printf '%b\n' "  ${YELLOW}--dry-run${NC}   (com --run) Testa sem executar pm2"
}


cmd_logs() {
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}"
    printf '%b\n' "${BOLD}  Phonevox Automações — Logs${NC}"
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}\n"
    
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 100 "$LOG_FILE"
    else
        printf '%b\n' "${YELLOW}Log vazio ou não encontrado${NC}"
    fi
}

cmd_update() {
    require_root
    
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}"
    printf '%b\n' "${BOLD}  Atualizando Script${NC}"
    printf '%b\n' "${CYAN}════════════════════════════════════════${NC}\n"
    
    local repo_dir
    repo_dir=$(git rev-parse --show-toplevel 2>/dev/null) || die "Execute dentro do diretório do repositório git"
    
    if ! git -C "$repo_dir" pull; then
        die "Erro ao fazer git pull em $repo_dir"
    fi
    
    printf '%b\n' "${GREEN}✓ Git pull realizado${NC}\n"
    
    cp -f "$repo_dir/phonevox-automacoes.sh" /usr/local/sbin/phonevox-automacoes
    chmod 755 /usr/local/sbin/phonevox-automacoes
    printf '%b\n' "${GREEN}✓ Script atualizado em /usr/local/sbin/phonevox-automacoes${NC}"

    install_service
    printf '%b\n' "${GREEN}✓ Systemd units atualizados${NC}"
}

case "${1:---help}" in
    --install) cmd_install ;;
    --reconfig) cmd_reconfig ;;
    --run) shift; [[ "$1" == "--dry-run" ]] && DRY_RUN=1; cmd_run ;;
    --status) cmd_status ;;
    --logs) cmd_logs ;;
    --update) cmd_update ;;
    --start) cmd_start ;;
    --stop) cmd_stop ;;
    --help) cmd_help ;;
    *) cmd_help ;;
esac