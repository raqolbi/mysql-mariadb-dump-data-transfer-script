#!/usr/bin/env bash
# ============================================================
# Post Action Hook - Email Notification (MSMTP DIRECT)
# ============================================================
#
# PURPOSE
# ------------------------------------------------------------
# This script sends an email notification after a backup
# process finishes (SUCCESS or ERROR).
#
# WHY MSMTP ONLY?
# ------------------------------------------------------------
# - msmtp is the actual SMTP client (reliable, non-interactive)
# - Avoids mutt/mailx stdin & TTY issues
# - Full control over headers, body, and attachments
#
# FEATURES
# ------------------------------------------------------------
# - Plain text email (always readable)
# - RFC 5322 compliant message
# - Optional log attachment
# - Cron-safe (no prompts, no TTY)
# - Email failure will NOT break backup flow
#
# ARGUMENTS (FROM BACKUP SCRIPT)
# ------------------------------------------------------------
# $1 = STATUS        (SUCCESS / ERROR)
# $2 = DUMP_FILE     (Path to .sql dump file)
# $3 = LOG_FILE      (Path to log file)
# $4 = PROFILE_NAME  (Backup profile name)
#
# ============================================================

set -o pipefail

# ------------------------------------------------------------
# INPUT ARGUMENTS
# ------------------------------------------------------------
STATUS="$1"
DUMP_FILE="$2"
LOG_FILE="$3"
PROFILE="$4"

# ------------------------------------------------------------
# ENSURE HOME IS SET (IMPORTANT FOR CRON + MSMTP)
# ------------------------------------------------------------
# msmtp reads ~/.msmtprc from $HOME
# Cron may not define HOME properly
# ------------------------------------------------------------
export HOME="${HOME:-/home/$(whoami)}"

# ------------------------------------------------------------
# LOAD EMAIL CONFIGURATION
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMAIL_ENV_FILE="${SCRIPT_DIR}/post_action_email.env"

# If email config is missing, silently skip email
# (backup must NOT fail because of email)
if [[ ! -f "${EMAIL_ENV_FILE}" ]]; then
  echo "WARN: Email env file not found: ${EMAIL_ENV_FILE}" >> "${LOG_FILE}"
  exit 0
fi

set -o allexport
source "${EMAIL_ENV_FILE}"
set +o allexport

# ------------------------------------------------------------
# BASIC METADATA
# ------------------------------------------------------------
HOSTNAME="${EMAIL_HOSTNAME:-$(hostname)}"
DB_NAME="$(basename "${DUMP_FILE}" | cut -d'_' -f1)"
SUBJECT="${EMAIL_SUBJECT_PREFIX} ${STATUS} - ${PROFILE}"

# ------------------------------------------------------------
# ATTACHMENT POLICY
# ------------------------------------------------------------
# - ERROR   : always attach log
# - SUCCESS : attach log only if enabled in env
# ------------------------------------------------------------
ATTACH_LOG=false

if [[ "${STATUS}" == "ERROR" ]]; then
  ATTACH_LOG=true
elif [[ "${STATUS}" == "SUCCESS" && "${EMAIL_ATTACH_LOG_ON_SUCCESS}" == "true" ]]; then
  ATTACH_LOG=true
fi

# ------------------------------------------------------------
# BUILD EMAIL (RFC 5322)
# ------------------------------------------------------------
TMP_MAIL="$(mktemp)"

{
  echo "From: ${EMAIL_FROM}"
  echo "To: ${EMAIL_TO}"
  echo "Subject: ${SUBJECT}"
  echo "MIME-Version: 1.0"

  if [[ "${ATTACH_LOG}" == true && -f "${LOG_FILE}" ]]; then
    # Multipart email (text + attachment)
    BOUNDARY="====MYSQL_BACKUP_$(date +%s)_BOUNDARY===="
    echo "Content-Type: multipart/mixed; boundary=\"${BOUNDARY}\""
    echo
    echo "--${BOUNDARY}"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo
  else
    # Simple text email
    echo "Content-Type: text/plain; charset=UTF-8"
    echo
  fi

  # ----------------------------------------------------------
  # EMAIL BODY
  # ----------------------------------------------------------
  cat <<EOF
MySQL Backup Notification

Host        : ${HOSTNAME}
Profile     : ${PROFILE}
Database    : ${DB_NAME}
Status      : ${STATUS}
Dump File   : ${DUMP_FILE}

Log File:
${LOG_FILE}

This message was generated automatically.
EOF

  # ----------------------------------------------------------
  # ATTACH LOG FILE (OPTIONAL)
  # ----------------------------------------------------------
  if [[ "${ATTACH_LOG}" == true && -f "${LOG_FILE}" ]]; then
    echo
    echo "--${BOUNDARY}"
    echo "Content-Type: text/plain; name=\"$(basename "${LOG_FILE}")\""
    echo "Content-Disposition: attachment; filename=\"$(basename "${LOG_FILE}")\""
    echo
    cat "${LOG_FILE}"
    echo
    echo "--${BOUNDARY}--"
  fi
} > "${TMP_MAIL}"

# ------------------------------------------------------------
# SEND EMAIL VIA MSMTP
# ------------------------------------------------------------
msmtp "${EMAIL_TO}" < "${TMP_MAIL}" || \
  echo "WARN: msmtp failed to send email" >> "${LOG_FILE}"

rm -f "${TMP_MAIL}"

exit 0
