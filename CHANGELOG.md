# Changelog

All notable changes to this project will be documented in this file.

This project follows **Semantic Versioning**.

---

## [1.0.0] - 2026-01-04

### Added

- Initial stable release of MySQL / MariaDB backup & restore runner
- Automatic multi-environment execution (`configs/*.env`)
- Single script architecture (no duplication per environment)
- Live backup progress:
  - Database name
  - Dump file size
  - Running time (single-line, non-noisy)
- Live restore running time
- Optional restore to target database (migration / replication use case)
- Per-profile log directory structure
- Audit-ready log format with clear start/end markers
- SSL support for source and target connections
- Post-action hook system (SUCCESS / ERROR)
- Example post-action hook implementation
- Email notification post-action:
  - Separate email environment configuration (`post_action_email.env`)
  - SUCCESS and ERROR notifications
  - Reliable log attachment using mutt
  - SMTP delivery via msmtp
  - Automatic log attachment on ERROR
  - Optional log attachment on SUCCESS
- Cron-safe, non-interactive execution
- Clear and production-oriented project documentation (README)

### Improved

- Connection handling reliability:
  - Pre-connection availability check using `mysqladmin ping`
  - Explicit connection timeout handling without interrupting running dumps
  - Avoids use of `timeout` around `mysqldump` to prevent data corruption
- Email delivery robustness:
  - Avoids `mailx` for attachments due to inconsistent behavior
  - Uses `mutt` exclusively for composing messages and handling attachments
  - Uses `msmtp` exclusively for SMTP transport
- Script resilience:
  - Each backup profile is isolated (failure does not affect others)
  - Clear separation between backup logic and notification logic

### Security

- No credentials stored in scripts
- Sensitive configuration isolated in `.env` files
- Email delivery split by responsibility:
  - SMTP handled by msmtp
  - Email composition and attachments handled by mutt
- Recommended permission hardening:
  - `chmod 600` for all `.env` files
  - `chmod 700` for executable scripts

### Notes

- This version represents the final hardened implementation of v1.0.0
- Timeout handling is intentionally implemented as pre-connection checks
  rather than process termination
- Designed for real infrastructure usage:
  - Large databases
  - Slow networks
  - Cron execution
- Email attachment handling intentionally avoids `mailx` due to
  inconsistent behavior across Linux distributions

---

Release Status:

- Stable
- Production-ready
