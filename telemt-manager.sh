#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_NAME="telemt"
INSTALL_ROOT="/opt/${PROJECT_NAME}"
CONFIG_DIR="${INSTALL_ROOT}/telemt-config"
CONFIG_FILE="${CONFIG_DIR}/telemt.toml"
COMPOSE_FILE="${INSTALL_ROOT}/docker-compose.yml"
STATE_FILE="${INSTALL_ROOT}/install.env"
MANAGED_SCRIPT_PATH="${INSTALL_ROOT}/telemt-manager.sh"
BACKUP_DIR="${INSTALL_ROOT}/backups"
SERVICE_NAME="${PROJECT_NAME}.service"
AUTOUPDATE_SERVICE_NAME="${PROJECT_NAME}-autoupdate.service"
AUTOUPDATE_TIMER_NAME="${PROJECT_NAME}-autoupdate.timer"
IMAGE_NAME="whn0thacked/telemt-docker:latest"
DEFAULT_PROXY_PORT="443"
DEFAULT_API_PORT="9091"
DEFAULT_METRICS_PORT="9090"
DEFAULT_PROXY_USER="hello"
DEFAULT_AUTOUPDATE_SCHEDULE="hourly"

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)/$(basename "${SCRIPT_PATH}")"

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдена команда: $1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

run_as_root() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

run_in_shell_as_root() {
  if is_root; then
    bash -lc "$1"
  else
    sudo bash -lc "$1"
  fi
}

write_root_file() {
  local target="${1}"
  if is_root; then
    cat > "${target}"
  else
    sudo tee "${target}" >/dev/null
  fi
}

ensure_base_dependencies() {
  need_cmd bash
  need_cmd awk
  need_cmd sed
  need_cmd grep
  need_cmd install
  need_cmd mkdir
  need_cmd chmod
  need_cmd cp
  need_cmd date
  need_cmd systemctl
  need_cmd docker
  if ! is_root; then
    need_cmd sudo
  fi
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN=(docker compose)
  elif have_cmd docker-compose; then
    COMPOSE_BIN=(docker-compose)
  else
    die "Не найден ни 'docker compose', ни 'docker-compose'"
  fi
}

compose() {
  "${COMPOSE_BIN[@]}" -f "${COMPOSE_FILE}" "$@"
}

state_get() {
  local key="${1}"
  [ -f "${STATE_FILE}" ] || return 1
  awk -F= -v key="${key}" '$1 == key { sub(/^[^=]*=/, "", $0); print $0; exit }' "${STATE_FILE}"
}

save_state() {
  local mask_domain="${1}"
  local public_host="${2}"
  local proxy_port="${3}"
  local api_port="${4}"
  local metrics_enabled="${5}"
  local metrics_port="${6}"
  local proxy_user="${7}"
  local proxy_secret="${8}"

  run_as_root mkdir -p "${INSTALL_ROOT}"
  cat <<EOF | write_root_file "${STATE_FILE}"
MASK_DOMAIN=${mask_domain}
PUBLIC_HOST=${public_host}
PROXY_PORT=${proxy_port}
API_PORT=${api_port}
METRICS_ENABLED=${metrics_enabled}
METRICS_PORT=${metrics_port}
PROXY_USER=${proxy_user}
PROXY_SECRET=${proxy_secret}
IMAGE_NAME=${IMAGE_NAME}
EOF
  run_as_root chmod 600 "${STATE_FILE}"
}

require_installation() {
  [ -f "${COMPOSE_FILE}" ] || die "Telemt ещё не установлен. Сначала запусти установку."
}

generate_secret() {
  local secret=""

  if have_cmd openssl; then
    secret="$(openssl rand -hex 16 2>/dev/null || true)"
  fi

  if [ "${#secret}" -ne 32 ]; then
    secret="$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  fi

  [ "${#secret}" -eq 32 ] || die "Не удалось сгенерировать 32-hex-char secret"
  printf '%s\n' "${secret}"
}

prompt_default() {
  local label="${1}"
  local default_value="${2}"
  local answer=""
  read -r -p "${label} [${default_value}]: " answer
  if [ -z "${answer}" ]; then
    printf '%s\n' "${default_value}"
  else
    printf '%s\n' "${answer}"
  fi
}

prompt_yes_no() {
  local label="${1}"
  local default_value="${2}"
  local answer=""

  while true; do
    read -r -p "${label} [${default_value}]: " answer
    answer="${answer:-${default_value}}"
    case "${answer}" in
      y|Y|yes|YES|да|Да|ДА) return 0 ;;
      n|N|no|NO|нет|Нет|НЕТ) return 1 ;;
      *) warn "Ответь yes/y/да или no/n/нет." ;;
    esac
  done
}

validate_domain() {
  local domain="${1}"
  printf '%s' "${domain}" | grep -Eq '^[A-Za-z0-9.-]+$'
}

validate_port() {
  local port="${1}"
  printf '%s' "${port}" | grep -Eq '^[0-9]+$' || return 1
  [ "${port}" -ge 1 ] && [ "${port}" -le 65535 ]
}

validate_secret() {
  local secret="${1}"
  printf '%s' "${secret}" | grep -Eq '^[0-9a-f]{32}$'
}

escape_toml_string() {
  printf '%s' "${1}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ensure_layout() {
  run_as_root mkdir -p "${INSTALL_ROOT}" "${CONFIG_DIR}" "${BACKUP_DIR}"
  run_as_root chmod 755 "${INSTALL_ROOT}"
  run_as_root chmod 777 "${CONFIG_DIR}"
  run_as_root chmod 755 "${BACKUP_DIR}"
}

install_script_copy() {
  run_as_root install -m 755 "${SCRIPT_PATH}" "${MANAGED_SCRIPT_PATH}"
}

backup_current_config() {
  local timestamp=""
  local target_dir=""

  ensure_layout
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  target_dir="${BACKUP_DIR}/${timestamp}"

  run_as_root mkdir -p "${target_dir}"
  [ -f "${CONFIG_FILE}" ] && run_as_root cp "${CONFIG_FILE}" "${target_dir}/telemt.toml"
  [ -f "${COMPOSE_FILE}" ] && run_as_root cp "${COMPOSE_FILE}" "${target_dir}/docker-compose.yml"
  [ -f "${STATE_FILE}" ] && run_as_root cp "${STATE_FILE}" "${target_dir}/install.env"
  [ -f "${MANAGED_SCRIPT_PATH}" ] && run_as_root cp "${MANAGED_SCRIPT_PATH}" "${target_dir}/telemt-manager.sh"

  printf '%s\n' "${target_dir}"
}

list_backups() {
  require_installation
  if ! run_as_root test -d "${BACKUP_DIR}"; then
    info "Backup'ов пока нет."
    return 0
  fi

  info "Доступные backup'ы:"
  run_as_root ls -1 "${BACKUP_DIR}" 2>/dev/null || true
}

restore_backup() {
  require_installation
  ensure_layout
  list_backups

  local backup_name=""
  local source_dir=""

  read -r -p 'Введите имя backup каталога для восстановления: ' backup_name
  [ -n "${backup_name}" ] || die "Имя backup не указано."

  source_dir="${BACKUP_DIR}/${backup_name}"
  run_as_root test -d "${source_dir}" || die "Backup не найден: ${source_dir}"

  backup_current_config >/dev/null
  [ -f "${source_dir}/telemt.toml" ] && run_as_root cp "${source_dir}/telemt.toml" "${CONFIG_FILE}"
  [ -f "${source_dir}/docker-compose.yml" ] && run_as_root cp "${source_dir}/docker-compose.yml" "${COMPOSE_FILE}"
  [ -f "${source_dir}/install.env" ] && run_as_root cp "${source_dir}/install.env" "${STATE_FILE}"
  [ -f "${source_dir}/telemt-manager.sh" ] && run_as_root cp "${source_dir}/telemt-manager.sh" "${MANAGED_SCRIPT_PATH}"

  run_as_root chmod 666 "${CONFIG_FILE}" >/dev/null 2>&1 || true
  run_as_root chmod 644 "${COMPOSE_FILE}" >/dev/null 2>&1 || true
  run_as_root chmod 600 "${STATE_FILE}" >/dev/null 2>&1 || true
  run_as_root chmod 755 "${MANAGED_SCRIPT_PATH}" >/dev/null 2>&1 || true

  write_systemd_units
  run_as_root systemctl enable --now "${SERVICE_NAME}"
  update_telemt
  info "Backup восстановлен: ${backup_name}"
}

get_required_state() {
  local key="${1}"
  local value=""

  value="$(state_get "${key}" || true)"
  [ -n "${value}" ] || die "В install.env отсутствует ${key}"
  printf '%s\n' "${value}"
}

write_compose_file() {
  local proxy_port="${1}"
  local api_port="${2}"
  local metrics_enabled="${3}"
  local metrics_port="${4}"
  local root_mode="false"
  local security_block=""

  if [ "${proxy_port}" -lt 1024 ]; then
    root_mode="true"
  fi

  if [ "${root_mode}" = "true" ]; then
    security_block='    user: "root"
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m'
  else
    security_block='    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m'
  fi

  cat <<EOF | write_root_file "${COMPOSE_FILE}"
services:
  telemt:
    image: ${IMAGE_NAME}
    container_name: telemt
    restart: unless-stopped
    environment:
      RUST_LOG: info
    command: ["/etc/telemt/telemt.toml"]
    volumes:
      - ${CONFIG_DIR}:/etc/telemt
    network_mode: host
${security_block}
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

  run_as_root chmod 644 "${COMPOSE_FILE}"
}

write_config_file() {
  local mask_domain="${1}"
  local public_host="${2}"
  local proxy_port="${3}"
  local api_port="${4}"
  local metrics_enabled="${5}"
  local metrics_port="${6}"
  local proxy_user="${7}"
  local proxy_secret="${8}"

  local metrics_block=""
  local escaped_mask_domain
  local escaped_public_host

  escaped_mask_domain="$(escape_toml_string "${mask_domain}")"
  escaped_public_host="$(escape_toml_string "${public_host}")"

  if [ "${metrics_enabled}" = "yes" ]; then
    metrics_block="metrics_port = ${metrics_port}"
  else
    metrics_block="# metrics_port = ${metrics_port}"
  fi

  cat <<EOF | write_root_file "${CONFIG_FILE}"
[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
public_host = "${escaped_public_host}"
public_port = ${proxy_port}

[server]
port = ${proxy_port}
${metrics_block}

[server.api]
enabled = true
listen = "127.0.0.1:${api_port}"
whitelist = ["127.0.0.0/8", "::1/128"]
minimal_runtime_enabled = false
minimal_runtime_cache_ttl_ms = 1000

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "${escaped_mask_domain}"
mask = true
tls_emulation = true
tls_front_dir = "tlsfront"

[access.users]
"${proxy_user}" = "${proxy_secret}"
EOF

  run_as_root chmod 666 "${CONFIG_FILE}"
}

write_systemd_units() {
  cat <<EOF | write_root_file "/etc/systemd/system/${SERVICE_NAME}"
[Unit]
Description=Telemt Docker Compose stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_ROOT}
ExecStart=${MANAGED_SCRIPT_PATH} --start-service
ExecStop=${MANAGED_SCRIPT_PATH} --stop-service
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF | write_root_file "/etc/systemd/system/${AUTOUPDATE_SERVICE_NAME}"
[Unit]
Description=Telemt auto update
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${MANAGED_SCRIPT_PATH} --auto-update-run
TimeoutStartSec=0
EOF

  cat <<EOF | write_root_file "/etc/systemd/system/${AUTOUPDATE_TIMER_NAME}"
[Unit]
Description=Run Telemt auto update every hour

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Unit=${AUTOUPDATE_SERVICE_NAME}
Persistent=true

[Install]
WantedBy=timers.target
EOF

  run_as_root systemctl daemon-reload
}

remove_systemd_units() {
  if systemctl list-unit-files | grep -Fq "${AUTOUPDATE_TIMER_NAME}"; then
    run_as_root systemctl disable --now "${AUTOUPDATE_TIMER_NAME}" >/dev/null 2>&1 || true
  fi

  if systemctl list-unit-files | grep -Fq "${AUTOUPDATE_SERVICE_NAME}"; then
    run_as_root systemctl disable --now "${AUTOUPDATE_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  if systemctl list-unit-files | grep -Fq "${SERVICE_NAME}"; then
    run_as_root systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  run_as_root rm -f "/etc/systemd/system/${SERVICE_NAME}"
  run_as_root rm -f "/etc/systemd/system/${AUTOUPDATE_SERVICE_NAME}"
  run_as_root rm -f "/etc/systemd/system/${AUTOUPDATE_TIMER_NAME}"
  run_as_root systemctl daemon-reload
}

start_service() {
  require_installation
  ensure_base_dependencies
  compose up -d
}

stop_service() {
  require_installation
  ensure_base_dependencies
  compose down --remove-orphans
}

docker_pull_with_change_detection() {
  local before_id=""
  local after_id=""

  before_id="$(docker image inspect "${IMAGE_NAME}" --format '{{.Id}}' 2>/dev/null || true)"
  compose pull telemt
  after_id="$(docker image inspect "${IMAGE_NAME}" --format '{{.Id}}' 2>/dev/null || true)"

  if [ -z "${before_id}" ] || [ "${before_id}" != "${after_id}" ]; then
    return 0
  fi

  return 1
}

update_telemt() {
  require_installation
  ensure_base_dependencies

  info "Проверяю наличие обновлений образа ${IMAGE_NAME}"
  if docker_pull_with_change_detection; then
    info "Найдено новое обновление, перезапускаю стек"
    compose up -d --force-recreate
  else
    info "Новых образов не найдено, проверяю что стек запущен"
    compose up -d
  fi
}

auto_update_run() {
  update_telemt
}

collect_configuration() {
  local current_mask_domain="${1:-}"
  local current_public_host="${2:-}"
  local current_proxy_port="${3:-${DEFAULT_PROXY_PORT}}"
  local current_api_port="${4:-${DEFAULT_API_PORT}}"
  local current_metrics_enabled="${5:-no}"
  local current_metrics_port="${6:-${DEFAULT_METRICS_PORT}}"
  local current_proxy_user="${7:-${DEFAULT_PROXY_USER}}"

  local mask_domain=""
  local public_host=""
  local proxy_port=""
  local api_port=""
  local metrics_enabled=""
  local metrics_port=""
  local proxy_user=""
  local proxy_secret=""

  while true; do
    mask_domain="$(prompt_default 'Домен для TLS-маскировки (например, google.com)' "${current_mask_domain:-google.com}")"
    validate_domain "${mask_domain}" && break
    warn "Некорректный домен."
  done

  while true; do
    public_host="$(prompt_default 'Публичный домен/IP для tg:// ссылки' "${current_public_host:-${mask_domain}}")"
    validate_domain "${public_host}" && break
    warn "Некорректный домен или IP."
  done

  while true; do
    proxy_port="$(prompt_default 'Порт Telemt' "${current_proxy_port}")"
    validate_port "${proxy_port}" && break
    warn "Некорректный порт."
  done

  while true; do
    api_port="$(prompt_default 'Локальный API port Telemt' "${current_api_port}")"
    validate_port "${api_port}" && break
    warn "Некорректный порт."
  done

  if prompt_yes_no 'Включить metrics port?' "${current_metrics_enabled}"; then
    metrics_enabled="yes"
    while true; do
      metrics_port="$(prompt_default 'Metrics port' "${current_metrics_port}")"
      validate_port "${metrics_port}" && break
      warn "Некорректный порт."
    done
  else
    metrics_enabled="no"
    metrics_port="${current_metrics_port}"
  fi

  while true; do
    proxy_user="$(prompt_default 'Имя пользователя для proxy-ссылки' "${current_proxy_user}")"
    printf '%s' "${proxy_user}" | grep -Eq '^[A-Za-z0-9_.-]+$' && break
    warn "Допустимы только буквы, цифры, '.', '_' и '-'."
  done

  proxy_secret="$(generate_secret)"
  validate_secret "${proxy_secret}" || die "Сгенерирован некорректный secret"

  COLLECTED_MASK_DOMAIN="${mask_domain}"
  COLLECTED_PUBLIC_HOST="${public_host}"
  COLLECTED_PROXY_PORT="${proxy_port}"
  COLLECTED_API_PORT="${api_port}"
  COLLECTED_METRICS_ENABLED="${metrics_enabled}"
  COLLECTED_METRICS_PORT="${metrics_port}"
  COLLECTED_PROXY_USER="${proxy_user}"
  COLLECTED_PROXY_SECRET="${proxy_secret}"
}

hex_encode() {
  printf '%s' "${1}" | od -An -tx1 | tr -d ' \n'
}

show_connection_info() {
  local public_host="${1}"
  local proxy_port="${2}"
  local proxy_user="${3}"
  local proxy_secret="${4}"
  local mask_domain="${5}"
  local mask_domain_hex=""

  mask_domain_hex="$(hex_encode "${mask_domain}")"

  printf '\n'
  info "Установка/обновление конфига завершены."
  printf 'Пользователь: %s\n' "${proxy_user}"
  printf 'Secret: %s\n' "${proxy_secret}"
  printf 'tg:// link: tg://proxy?server=%s&port=%s&secret=ee%s%s\n' "${public_host}" "${proxy_port}" "${proxy_secret}" "${mask_domain_hex}"
  printf '\n'
}

show_status() {
  require_installation
  ensure_base_dependencies

  printf '\n[STATUS] systemd service\n'
  systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || true
  systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true

  printf '\n[STATUS] auto-update timer\n'
  systemctl is-enabled "${AUTOUPDATE_TIMER_NAME}" 2>/dev/null || true
  systemctl is-active "${AUTOUPDATE_TIMER_NAME}" 2>/dev/null || true

  printf '\n[STATUS] container\n'
  docker ps -a --filter "name=^telemt$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

  printf '\n[STATUS] compose\n'
  compose ps || true
  printf '\n'
}

show_current_config_summary() {
  require_installation

  local mask_domain=""
  local public_host=""
  local proxy_port=""
  local api_port=""
  local metrics_enabled=""
  local metrics_port=""
  local proxy_user=""
  local proxy_secret=""

  mask_domain="$(get_required_state MASK_DOMAIN)"
  public_host="$(get_required_state PUBLIC_HOST)"
  proxy_port="$(get_required_state PROXY_PORT)"
  api_port="$(get_required_state API_PORT)"
  metrics_enabled="$(get_required_state METRICS_ENABLED)"
  metrics_port="$(get_required_state METRICS_PORT)"
  proxy_user="$(get_required_state PROXY_USER)"
  proxy_secret="$(get_required_state PROXY_SECRET)"

  printf '\n'
  printf 'Mask domain: %s\n' "${mask_domain}"
  printf 'Public host: %s\n' "${public_host}"
  printf 'Proxy port: %s\n' "${proxy_port}"
  printf 'API port: %s\n' "${api_port}"
  printf 'Metrics enabled: %s\n' "${metrics_enabled}"
  printf 'Metrics port: %s\n' "${metrics_port}"
  printf 'Proxy user: %s\n' "${proxy_user}"
  printf 'Secret: %s\n' "${proxy_secret}"
  printf 'Auto-update timer: '
  systemctl is-enabled "${AUTOUPDATE_TIMER_NAME}" 2>/dev/null || printf 'disabled\n'
  printf '\n'
}

restart_telemt() {
  require_installation
  ensure_base_dependencies
  run_as_root systemctl restart "${SERVICE_NAME}"
  info "Telemt перезапущен."
}

show_logs() {
  require_installation
  ensure_base_dependencies
  compose logs --tail=100 -f telemt
}

rotate_secret_only() {
  require_installation
  ensure_base_dependencies

  local backup_path=""
  local mask_domain=""
  local public_host=""
  local proxy_port=""
  local api_port=""
  local metrics_enabled=""
  local metrics_port=""
  local proxy_user=""
  local proxy_secret=""

  backup_path="$(backup_current_config)"
  info "Создан backup: ${backup_path}"

  mask_domain="$(get_required_state MASK_DOMAIN)"
  public_host="$(get_required_state PUBLIC_HOST)"
  proxy_port="$(get_required_state PROXY_PORT)"
  api_port="$(get_required_state API_PORT)"
  metrics_enabled="$(get_required_state METRICS_ENABLED)"
  metrics_port="$(get_required_state METRICS_PORT)"
  proxy_user="$(get_required_state PROXY_USER)"
  proxy_secret="$(generate_secret)"

  write_config_file \
    "${mask_domain}" \
    "${public_host}" \
    "${proxy_port}" \
    "${api_port}" \
    "${metrics_enabled}" \
    "${metrics_port}" \
    "${proxy_user}" \
    "${proxy_secret}"

  save_state \
    "${mask_domain}" \
    "${public_host}" \
    "${proxy_port}" \
    "${api_port}" \
    "${metrics_enabled}" \
    "${metrics_port}" \
    "${proxy_user}" \
    "${proxy_secret}"

  restart_telemt
  show_connection_info "${public_host}" "${proxy_port}" "${proxy_user}" "${proxy_secret}" "${mask_domain}"
}

change_mask_domain_only() {
  require_installation
  ensure_base_dependencies

  local backup_path=""
  local mask_domain=""
  local public_host=""
  local proxy_port=""
  local api_port=""
  local metrics_enabled=""
  local metrics_port=""
  local proxy_user=""
  local proxy_secret=""
  local new_mask_domain=""

  backup_path="$(backup_current_config)"
  info "Создан backup: ${backup_path}"

  mask_domain="$(get_required_state MASK_DOMAIN)"
  public_host="$(get_required_state PUBLIC_HOST)"
  proxy_port="$(get_required_state PROXY_PORT)"
  api_port="$(get_required_state API_PORT)"
  metrics_enabled="$(get_required_state METRICS_ENABLED)"
  metrics_port="$(get_required_state METRICS_PORT)"
  proxy_user="$(get_required_state PROXY_USER)"
  proxy_secret="$(get_required_state PROXY_SECRET)"

  while true; do
    new_mask_domain="$(prompt_default 'Новый домен для TLS-маскировки' "${mask_domain}")"
    validate_domain "${new_mask_domain}" && break
    warn "Некорректный домен."
  done

  write_config_file \
    "${new_mask_domain}" \
    "${public_host}" \
    "${proxy_port}" \
    "${api_port}" \
    "${metrics_enabled}" \
    "${metrics_port}" \
    "${proxy_user}" \
    "${proxy_secret}"

  save_state \
    "${new_mask_domain}" \
    "${public_host}" \
    "${proxy_port}" \
    "${api_port}" \
    "${metrics_enabled}" \
    "${metrics_port}" \
    "${proxy_user}" \
    "${proxy_secret}"

  restart_telemt
  show_connection_info "${public_host}" "${proxy_port}" "${proxy_user}" "${proxy_secret}" "${new_mask_domain}"
}

check_mask_domain() {
  require_installation
  need_cmd curl

  local mask_domain=""
  mask_domain="$(get_required_state MASK_DOMAIN)"

  info "Проверяю https://${mask_domain}"
  curl -I -L --max-time 15 --connect-timeout 5 "https://${mask_domain}"
}

check_port() {
  local port="${1}"

  printf 'Port %s: ' "${port}"
  if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    printf 'занят\n'
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN
  else
    printf 'свободен\n'
  fi
  printf '\n'
}

check_ports() {
  require_installation
  need_cmd lsof

  local proxy_port=""
  local api_port=""
  local metrics_enabled=""
  local metrics_port=""

  proxy_port="$(get_required_state PROXY_PORT)"
  api_port="$(get_required_state API_PORT)"
  metrics_enabled="$(get_required_state METRICS_ENABLED)"
  metrics_port="$(get_required_state METRICS_PORT)"

  check_port "${proxy_port}"
  check_port "${api_port}"
  if [ "${metrics_enabled}" = "yes" ]; then
    check_port "${metrics_port}"
  fi
}

sync_manager_script() {
  require_installation
  ensure_base_dependencies
  install_script_copy
  write_systemd_units
  info "Скрипт-менеджер синхронизирован в ${MANAGED_SCRIPT_PATH}"
}

install_or_reconfigure() {
  ensure_base_dependencies
  ensure_layout
  install_script_copy

  local current_mask_domain=""
  local current_public_host=""
  local current_proxy_port="${DEFAULT_PROXY_PORT}"
  local current_api_port="${DEFAULT_API_PORT}"
  local current_metrics_enabled="no"
  local current_metrics_port="${DEFAULT_METRICS_PORT}"
  local current_proxy_user="${DEFAULT_PROXY_USER}"

  current_mask_domain="$(state_get MASK_DOMAIN || true)"
  current_public_host="$(state_get PUBLIC_HOST || true)"
  current_proxy_port="$(state_get PROXY_PORT || printf '%s\n' "${DEFAULT_PROXY_PORT}")"
  current_api_port="$(state_get API_PORT || printf '%s\n' "${DEFAULT_API_PORT}")"
  current_metrics_enabled="$(state_get METRICS_ENABLED || printf 'no\n')"
  current_metrics_port="$(state_get METRICS_PORT || printf '%s\n' "${DEFAULT_METRICS_PORT}")"
  current_proxy_user="$(state_get PROXY_USER || printf '%s\n' "${DEFAULT_PROXY_USER}")"

  if [ -f "${COMPOSE_FILE}" ] || [ -f "${STATE_FILE}" ]; then
    info "Сохраняю backup текущей конфигурации перед изменениями"
    backup_current_config >/dev/null
  fi

  collect_configuration \
    "${current_mask_domain}" \
    "${current_public_host}" \
    "${current_proxy_port}" \
    "${current_api_port}" \
    "${current_metrics_enabled}" \
    "${current_metrics_port}" \
    "${current_proxy_user}"

  write_compose_file \
    "${COLLECTED_PROXY_PORT}" \
    "${COLLECTED_API_PORT}" \
    "${COLLECTED_METRICS_ENABLED}" \
    "${COLLECTED_METRICS_PORT}"

  write_config_file \
    "${COLLECTED_MASK_DOMAIN}" \
    "${COLLECTED_PUBLIC_HOST}" \
    "${COLLECTED_PROXY_PORT}" \
    "${COLLECTED_API_PORT}" \
    "${COLLECTED_METRICS_ENABLED}" \
    "${COLLECTED_METRICS_PORT}" \
    "${COLLECTED_PROXY_USER}" \
    "${COLLECTED_PROXY_SECRET}"

  save_state \
    "${COLLECTED_MASK_DOMAIN}" \
    "${COLLECTED_PUBLIC_HOST}" \
    "${COLLECTED_PROXY_PORT}" \
    "${COLLECTED_API_PORT}" \
    "${COLLECTED_METRICS_ENABLED}" \
    "${COLLECTED_METRICS_PORT}" \
    "${COLLECTED_PROXY_USER}" \
    "${COLLECTED_PROXY_SECRET}"

  write_systemd_units
  run_as_root systemctl enable --now "${SERVICE_NAME}"
  update_telemt
  show_connection_info \
    "${COLLECTED_PUBLIC_HOST}" \
    "${COLLECTED_PROXY_PORT}" \
    "${COLLECTED_PROXY_USER}" \
    "${COLLECTED_PROXY_SECRET}" \
    "${COLLECTED_MASK_DOMAIN}"
}

disable_everything() {
  require_installation
  ensure_base_dependencies
  run_as_root systemctl disable --now "${AUTOUPDATE_TIMER_NAME}" >/dev/null 2>&1 || true
  run_as_root systemctl disable --now "${AUTOUPDATE_SERVICE_NAME}" >/dev/null 2>&1 || true
  run_as_root systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  compose down --remove-orphans || true
  info "Telemt и связанные systemd unit'ы выключены."
}

purge_everything() {
  if [ -f "${COMPOSE_FILE}" ]; then
    ensure_base_dependencies
    compose down --remove-orphans --volumes || true
  fi

  remove_systemd_units
  run_as_root rm -rf "${INSTALL_ROOT}"
  info "Telemt полностью удалён."
}

enable_autoupdate() {
  require_installation
  install_script_copy
  write_systemd_units
  run_as_root systemctl enable --now "${AUTOUPDATE_TIMER_NAME}"
  info "Автообновление включено."
}

disable_autoupdate() {
  require_installation
  run_as_root systemctl disable --now "${AUTOUPDATE_TIMER_NAME}" >/dev/null 2>&1 || true
  info "Автообновление выключено."
}

print_menu() {
  cat <<'EOF'

Выбери действие:
1. Обновить telemt
2. Обновить конфиг
3. Выключить полностью telemt и все systemd юниты
4. Удалить полностью telemt
5. Включить автообновление
6. Выключить автообновление
7. Показать текущий статус
8. Показать текущий конфиг
9. Перезапустить telemt
10. Показать логи
11. Сгенерировать новый secret без смены остального
12. Изменить только домен маскировки
13. Проверить доступность домена маскировки
14. Проверить порты и конфликты
15. Обновить сам скрипт-менеджер
16. Сделать backup конфига
17. Восстановить backup конфига
0. Выход

EOF
}

interactive_menu() {
  local action=""
  while true; do
    print_menu
    read -r -p 'Пункт меню: ' action
    case "${action}" in
      1) update_telemt ;;
      2) install_or_reconfigure ;;
      3) disable_everything ;;
      4)
        if prompt_yes_no 'Точно удалить telemt полностью?' 'no'; then
          purge_everything
          break
        fi
        ;;
      5) enable_autoupdate ;;
      6) disable_autoupdate ;;
      7) show_status ;;
      8) show_current_config_summary ;;
      9) restart_telemt ;;
      10) show_logs ;;
      11) rotate_secret_only ;;
      12) change_mask_domain_only ;;
      13) check_mask_domain ;;
      14) check_ports ;;
      15) sync_manager_script ;;
      16)
        info "Создан backup: $(backup_current_config)"
        ;;
      17) restore_backup ;;
      0) break ;;
      *) warn "Неизвестный пункт меню." ;;
    esac
  done
}

show_help() {
  cat <<EOF
Использование:
  ${0}                 - первичная установка или интерактивное меню
  ${0} --install       - установка / переустановка конфига
  ${0} --menu          - интерактивное меню
  ${0} --update        - обновить Telemt
  ${0} --reconfigure   - заново запросить домен и secret
  ${0} --disable       - выключить Telemt и systemd unit'ы
  ${0} --purge         - удалить Telemt полностью
  ${0} --enable-autoupdate
  ${0} --disable-autoupdate
  ${0} --status
  ${0} --show-config
  ${0} --restart
  ${0} --logs
  ${0} --rotate-secret
  ${0} --change-mask-domain
  ${0} --check-mask-domain
  ${0} --check-ports
  ${0} --sync-manager
  ${0} --backup
  ${0} --restore-backup
EOF
}

main() {
  local action="${1:-}"

  case "${action}" in
    --help|-h)
      show_help
      ;;
    --install)
      install_or_reconfigure
      ;;
    --menu)
      require_installation
      interactive_menu
      ;;
    --update)
      update_telemt
      ;;
    --reconfigure)
      require_installation
      install_or_reconfigure
      ;;
    --disable)
      disable_everything
      ;;
    --purge)
      purge_everything
      ;;
    --enable-autoupdate)
      enable_autoupdate
      ;;
    --disable-autoupdate)
      disable_autoupdate
      ;;
    --status)
      show_status
      ;;
    --show-config)
      show_current_config_summary
      ;;
    --restart)
      restart_telemt
      ;;
    --logs)
      show_logs
      ;;
    --rotate-secret)
      rotate_secret_only
      ;;
    --change-mask-domain)
      change_mask_domain_only
      ;;
    --check-mask-domain)
      check_mask_domain
      ;;
    --check-ports)
      check_ports
      ;;
    --sync-manager)
      sync_manager_script
      ;;
    --backup)
      require_installation
      info "Создан backup: $(backup_current_config)"
      ;;
    --restore-backup)
      restore_backup
      ;;
    --start-service)
      start_service
      ;;
    --stop-service)
      stop_service
      ;;
    --auto-update-run)
      auto_update_run
      ;;
    "")
      if [ -f "${COMPOSE_FILE}" ]; then
        interactive_menu
      else
        install_or_reconfigure
      fi
      ;;
    *)
      die "Неизвестный аргумент: ${action}"
      ;;
  esac
}

main "${@}"
