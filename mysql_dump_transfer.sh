#!/usr/bin/env bash
# ------------------------------------------------------------
# MySQL / MariaDB Dump and Optional Transfer Script
# ------------------------------------------------------------
# This script performs a database dump from a source MySQL/MariaDB
# server and optionally restores it to a target server.
#
# Features:
# - Timestamped dump filename
# - Per-run log file
# - Optional SSL support (source & target)
# - Optional restore to target database
# - Post-action hook after completion (SUCCESS / ERROR)
# - Safe for cron execution
# ------------------------------------------------------------

set -o pipefail

############################################################
# CONFIGURATION
############################################################

# ---------------- SOURCE DATABASE (REQUIRED) ----------------
SRC_HOST="localhost"
SRC_PORT="3306"
SRC_USER="root"
SRC_PASS="password"
SRC_DB="database_name"

# Enable SSL for source connection (true / false)
SRC_SSL_ENABLE=false
SRC_SSL_CA="/path/ssl/ca.pem"
SRC_SSL_CERT="/path/ssl/client-cert.pem"
SRC_SSL_KEY="/path/ssl/client-key.pem"

# ---------------- TARGET DATABASE (OPTIONAL) ----------------
# If TARGET_ENABLE=true, the dump will be restored to target DB
TARGET_ENABLE=false
DEST_HOST="localhost"
DEST_PORT="3306"
DEST_USER="root"
DEST_PASS="password"
DEST_DB="target_database"

# Enable SSL for target connection (true / false)
DEST_SSL_ENABLE=false
DEST_SSL_CA="/path/ssl/ca.pem"
DEST_SSL_CERT="/path/ssl/client-cert.pem"
DEST_SSL_KEY="/path/ssl/client-key.pem"

# ---------------- BACKUP OUTPUT ----------------
# Directory where dump and log files will be stored
DUMP_PATH="/var/backups/mysql"

# ---------------- POST ACTION ----------------
# Optional script executed after process finishes
# Arguments passed:
#   $1 = STATUS (SUCCESS / ERROR)
#   $2 = Dump file path
#   $3 = Log file path
POST_ACTION_SCRIPT=""

############################################################
# INITIALIZATION
############################################################

TIMESTAMP=$(date +"%Y-%m-%d_%H.%M.%S")
DUMP_FILE_NAME="${SRC_DB}_${TIMESTAMP}.sql"
LOG_FILE_NAME="${SRC_DB}_${TIMESTAMP}.log"

DUMP_FILE="${DUMP_PATH}/${DUMP_FILE_NAME}"
LOG_FILE="${DUMP_PATH}/${LOG_FILE_NAME}"

mkdir -p "${DUMP_PATH}"

# Write message to log file with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

# Handle failure, log error, run post-action, and exit
fail() {
  log "ERROR: $1"
  run_post_action "ERROR"
  exit 1
}

# Execute post-action script if configured
run_post_action() {
  local status="$1"
  if [[ -n "${POST_ACTION_SCRIPT}" && -x "${POST_ACTION_SCRIPT}" ]]; then
    "${POST_ACTION_SCRIPT}" "${status}" "${DUMP_FILE}" "${LOG_FILE}" >> "${LOG_FILE}" 2>&1
  fi
}

############################################################
# BUILD SSL PARAMETERS
############################################################

SRC_SSL_PARAMS=""
if [[ "${SRC_SSL_ENABLE}" == true ]]; then
  SRC_SSL_PARAMS="--ssl-mode=REQUIRED --ssl-ca=${SRC_SSL_CA} --ssl-cert=${SRC_SSL_CERT} --ssl-key=${SRC_SSL_KEY}"
fi

DEST_SSL_PARAMS=""
if [[ "${DEST_SSL_ENABLE}" == true ]]; then
  DEST_SSL_PARAMS="--ssl-mode=REQUIRED --ssl-ca=${DEST_SSL_CA} --ssl-cert=${DEST_SSL_CERT} --ssl-key=${DEST_SSL_KEY}"
fi

############################################################
# DUMP PROCESS
############################################################

log "Starting dump for database: ${SRC_DB}"

mysqldump \
  -h "${SRC_HOST}" \
  -P "${SRC_PORT}" \
  -u "${SRC_USER}" \
  -p"${SRC_PASS}" \
  ${SRC_SSL_PARAMS} \
  --single-transaction \
  --routines \
  --events \
  --triggers \
  "${SRC_DB}" > "${DUMP_FILE}" 2>>"${LOG_FILE}"

if [[ $? -ne 0 ]]; then
  fail "mysqldump failed"
fi

log "Dump completed successfully: ${DUMP_FILE}"

############################################################
# RESTORE PROCESS (OPTIONAL)
############################################################

if [[ "${TARGET_ENABLE}" == true ]]; then
  log "Starting restore to target database: ${DEST_DB}"

  mysql \
    -h "${DEST_HOST}" \
    -P "${DEST_PORT}" \
    -u "${DEST_USER}" \
    -p"${DEST_PASS}" \
    ${DEST_SSL_PARAMS} \
    "${DEST_DB}" < "${DUMP_FILE}" 2>>"${LOG_FILE}"

  if [[ $? -ne 0 ]]; then
    fail "Restore to target database failed"
  fi

  log "Restore completed successfully"
fi

############################################################
# FINISH
############################################################

log "Process finished successfully"
run_post_action "SUCCESS"
exit 0
