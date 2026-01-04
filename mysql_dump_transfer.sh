#!/usr/bin/env bash
# ============================================================
# MySQL / MariaDB Backup & Optional Restore Runner
# ============================================================
# Version: v1.0.0
#
# DESCRIPTION
# ------------------------------------------------------------
# Production-ready backup & restore runner for MySQL/MariaDB.
# Designed for cron execution and multi-environment usage.
#
# Each *.env file inside ./configs represents ONE backup profile.
#
# FEATURES
# ------------------------------------------------------------
# - Automatic multi-environment execution (configs/*.env)
# - Live single-line backup progress (DB, size, running time)
# - Optional restore with live running time
# - Pre-connection check with timeout (no dump interruption)
# - Post-action hook (SUCCESS / ERROR) per profile
# - SSL support (source & target)
# - Audit-ready per-profile logs
# - Cron-safe (non-interactive)
#
# IMPORTANT
# ------------------------------------------------------------
# - Only files ending with `.env` inside ./configs are executed
# - Files like `.env.example`, `.env.backup` are ignored
# - One `.env` = one isolated backup profile
# ============================================================

set -o pipefail

# ------------------------------------------------------------
# Base paths
# ------------------------------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${BASE_DIR}/configs"
LOG_ROOT="${BASE_DIR}/logs"

mkdir -p "${LOG_ROOT}"

# ------------------------------------------------------------
# Logging helper
# ------------------------------------------------------------
log() {
  local LOG_FILE="$1"; shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

# ------------------------------------------------------------
# Post-action executor
# ------------------------------------------------------------
# Arguments passed to post-action script:
# $1 = STATUS (SUCCESS / ERROR)
# $2 = Dump file path
# $3 = Log file path
# $4 = Profile name
# ------------------------------------------------------------
run_post_action() {
  local STATUS="$1"
  if [[ -n "${POST_ACTION_SCRIPT}" && -x "${POST_ACTION_SCRIPT}" ]]; then
    "${POST_ACTION_SCRIPT}" \
      "${STATUS}" \
      "${DUMP_FILE}" \
      "${LOG_FILE}" \
      "${PROFILE_NAME}" >> "${LOG_FILE}" 2>&1
  fi
}

# ------------------------------------------------------------
# Centralized failure handler (per profile)
# ------------------------------------------------------------
fail() {
  local MESSAGE="$1"
  log "${LOG_FILE}" "ERROR: ${MESSAGE}"
  run_post_action "ERROR"
  return 1
}

# ------------------------------------------------------------
# Connection availability checker
# ------------------------------------------------------------
# Polls database connectivity using mysqladmin ping.
# This avoids killing long-running dumps.
#
# Returns:
# 0 = reachable
# 1 = unreachable after TIMEOUT seconds
# ------------------------------------------------------------
check_mysql_connection() {
  local HOST="$1"
  local PORT="$2"
  local USER="$3"
  local PASS="$4"
  local TIMEOUT="$5"

  local START
  START=$(date +%s)

  while true; do
    mysqladmin \
      -h "${HOST}" \
      -P "${PORT}" \
      -u "${USER}" \
      -p"${PASS}" \
      ping --silent &>/dev/null && return 0

    (( $(date +%s) - START >= TIMEOUT )) && return 1
    sleep 1
  done
}

# ============================================================
# MAIN LOOP (MULTI ENV EXECUTION)
# ============================================================

for ENV_FILE in "${CONFIG_DIR}"/*.env; do
  [[ ! -f "${ENV_FILE}" ]] && continue

  # ----------------------------------------------------------
  # Load environment profile
  # ----------------------------------------------------------
  set -o allexport
  source "${ENV_FILE}"
  set +o allexport

  # ----------------------------------------------------------
  # Validate required variables
  # ----------------------------------------------------------
  REQUIRED_VARS=(SRC_HOST SRC_PORT SRC_USER SRC_PASS SRC_DB DUMP_PATH)
  for VAR in "${REQUIRED_VARS[@]}"; do
    [[ -z "${!VAR}" ]] && echo "ERROR: ${ENV_FILE} missing ${VAR}" && continue 2
  done

  PROFILE_NAME="$(basename "${ENV_FILE}" .env)"
  TIMESTAMP=$(date +"%Y-%m-%d_%H.%M.%S")

  PROFILE_LOG_DIR="${LOG_ROOT}/${PROFILE_NAME}"
  mkdir -p "${PROFILE_LOG_DIR}"

  DUMP_FILE="${DUMP_PATH}/${SRC_DB}_${TIMESTAMP}.sql"
  LOG_FILE="${PROFILE_LOG_DIR}/${SRC_DB}_${TIMESTAMP}.log"

  # ----------------------------------------------------------
  # Connection timeout defaults (seconds)
  # ----------------------------------------------------------
  SRC_CONNECT_TIMEOUT="${SRC_CONNECT_TIMEOUT:-30}"
  DEST_CONNECT_TIMEOUT="${DEST_CONNECT_TIMEOUT:-60}"

  # ----------------------------------------------------------
  # SSL parameters (optional)
  # ----------------------------------------------------------
  SRC_SSL_PARAMS=""
  [[ "${SRC_SSL_ENABLE}" == "true" ]] && \
    SRC_SSL_PARAMS="--ssl-mode=REQUIRED --ssl-ca=${SRC_SSL_CA} --ssl-cert=${SRC_SSL_CERT} --ssl-key=${SRC_SSL_KEY}"

  DEST_SSL_PARAMS=""
  [[ "${DEST_SSL_ENABLE}" == "true" ]] && \
    DEST_SSL_PARAMS="--ssl-mode=REQUIRED --ssl-ca=${DEST_SSL_CA} --ssl-cert=${DEST_SSL_CERT} --ssl-key=${DEST_SSL_KEY}"

  # ==========================================================
  # BACKUP
  # ==========================================================
  BACKUP_START=$(date +%s)
  log "${LOG_FILE}" "=== BACKUP STARTED ==="
  log "${LOG_FILE}" "Profile  : ${PROFILE_NAME}"
  log "${LOG_FILE}" "Database : ${SRC_DB}"
  log "${LOG_FILE}" "Dump     : ${DUMP_FILE}"

  # Live progress (single-line)
  backup_progress() {
    local PID="$1"
    while kill -0 "${PID}" 2>/dev/null; do
      SIZE_BYTES=$(stat -c%s "${DUMP_FILE}" 2>/dev/null || echo 0)
      SIZE_MB=$(awk "BEGIN {printf \"%.2f\", ${SIZE_BYTES}/1024/1024}")
      ELAPSED=$(( $(date +%s) - BACKUP_START ))
      ELAPSED_FMT=$(date -u -d @"${ELAPSED}" +"%H:%M:%S")
      printf "\rBACKUP RUNNING | Profile: %s | DB: %s | Size: %s MB | Time: %s" \
        "${PROFILE_NAME}" "${SRC_DB}" "${SIZE_MB}" "${ELAPSED_FMT}"
      sleep 1
    done
  }

  # Pre-check source connectivity
  if ! check_mysql_connection \
    "${SRC_HOST}" \
    "${SRC_PORT}" \
    "${SRC_USER}" \
    "${SRC_PASS}" \
    "${SRC_CONNECT_TIMEOUT}"; then

    fail "Source database unreachable after ${SRC_CONNECT_TIMEOUT}s"
    continue
  fi

  # Run dump
  mysqldump \
    -h "${SRC_HOST}" -P "${SRC_PORT}" \
    -u "${SRC_USER}" -p"${SRC_PASS}" \
    ${SRC_SSL_PARAMS} \
    --single-transaction --routines --events --triggers \
    "${SRC_DB}" > "${DUMP_FILE}" 2>> "${LOG_FILE}" &

  DUMP_PID=$!
  backup_progress "${DUMP_PID}" &
  BP_PID=$!

  wait "${DUMP_PID}"
  DUMP_EXIT=$?

  kill "${BP_PID}" 2>/dev/null
  wait "${BP_PID}" 2>/dev/null
  echo ""

  if [[ "${DUMP_EXIT}" -ne 0 ]]; then
    fail "Backup failed (mysqldump error)"
    continue
  fi

  BACKUP_TIME=$(date -u -d @"$(( $(date +%s) - BACKUP_START ))" +"%H:%M:%S")
  FINAL_SIZE_MB=$(du -m "${DUMP_FILE}" | awk '{print $1}')

  log "${LOG_FILE}" "BACKUP COMPLETED | Size: ${FINAL_SIZE_MB} MB | Time: ${BACKUP_TIME}"
  echo "BACKUP COMPLETED | Profile: ${PROFILE_NAME} | DB: ${SRC_DB} | Size: ${FINAL_SIZE_MB} MB | Time: ${BACKUP_TIME}"

  # ==========================================================
  # RESTORE (OPTIONAL)
  # ==========================================================
  if [[ "${TARGET_ENABLE}" == "true" ]]; then
    RESTORE_START=$(date +%s)
    log "${LOG_FILE}" "=== RESTORE STARTED ==="
    log "${LOG_FILE}" "Target DB: ${DEST_DB}"

    restore_progress() {
      local PID="$1"
      while kill -0 "${PID}" 2>/dev/null; do
        ELAPSED=$(( $(date +%s) - RESTORE_START ))
        ELAPSED_FMT=$(date -u -d @"${ELAPSED}" +"%H:%M:%S")
        printf "\rRESTORE RUNNING | Profile: %s | Target DB: %s | Time: %s" \
          "${PROFILE_NAME}" "${DEST_DB}" "${ELAPSED_FMT}"
        sleep 1
      done
    }

    if ! check_mysql_connection \
      "${DEST_HOST}" \
      "${DEST_PORT}" \
      "${DEST_USER}" \
      "${DEST_PASS}" \
      "${DEST_CONNECT_TIMEOUT}"; then

      fail "Target database unreachable after ${DEST_CONNECT_TIMEOUT}s"
      continue
    fi

    mysql \
      -h "${DEST_HOST}" -P "${DEST_PORT}" \
      -u "${DEST_USER}" -p"${DEST_PASS}" \
      ${DEST_SSL_PARAMS} \
      "${DEST_DB}" < "${DUMP_FILE}" 2>> "${LOG_FILE}" &

    RESTORE_PID=$!
    restore_progress "${RESTORE_PID}" &
    RP_PID=$!

    wait "${RESTORE_PID}"
    RESTORE_EXIT=$?

    kill "${RP_PID}" 2>/dev/null
    wait "${RP_PID}" 2>/dev/null
    echo ""

    if [[ "${RESTORE_EXIT}" -ne 0 ]]; then
      fail "Restore failed (apply error)"
      continue
    fi

    RESTORE_TIME=$(date -u -d @"$(( $(date +%s) - RESTORE_START ))" +"%H:%M:%S")
    log "${LOG_FILE}" "RESTORE COMPLETED | Time: ${RESTORE_TIME}"
    echo "RESTORE COMPLETED | Profile: ${PROFILE_NAME} | Target DB: ${DEST_DB} | Time: ${RESTORE_TIME}"
  fi

  # ----------------------------------------------------------
  # SUCCESS
  # ----------------------------------------------------------
  run_post_action "SUCCESS"

done

exit 0
