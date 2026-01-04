# MySQL / MariaDB Backup & Restore Script

Version: **v1.0.0 (Stable)**

A **production-ready Bash solution** for **multi-environment MySQL/MariaDB backup and optional restore**, designed for **real servers, cron jobs, and infrastructure operations** — not demos.

This project focuses on **reliability, auditability, and automation safety**.

---

## What This Project Solves

- Backup **many databases / servers** with **one script**
- Run safely via **cron (non-interactive)**
- See **live progress** without noisy logs
- Optionally **restore to another server** (migration / replication)
- Trigger **post-actions** (email, alerting, upload)
- Send **reliable email notifications with attachments**

---

## Key Features

- Automatic **multi-environment execution** (`configs/*.env`)
- Live backup progress (single-line):
  - Profile name
  - Database name
  - Dump size
  - Running time
- Optional restore with live running time
- Connection timeout handling (fail fast, notify)
- SSL support (source & target)
- Per-profile audit-ready logs
- Post-action hooks on **SUCCESS / ERROR**
- **Email notification with guaranteed body & attachment (msmtp direct)**
- Cron-safe, non-interactive execution

---

## Project Structure

```
mysql-backup/
├── mysql_dump_transfer.sh        # Main backup & restore runner
├── post_action_email.sh          # Email post-action hook (msmtp direct)
├── post_action_email.env         # Email configuration (DO NOT COMMIT)
├── configs/                      # Backup profiles (multi-env)
│   ├── prod.env
│   ├── staging.env
│   └── client-a.env
├── logs/                         # Per-profile logs (auto-created)
├── README.md
├── CHANGELOG.md
└── .gitignore
```

---

## How Multi-Environment Execution Works

- Every file ending with `.env` inside `configs/` is treated as **one backup profile**
- Files NOT ending with `.env` (e.g. `.env.example`, `.env.backup`) are ignored
- All profiles are executed **sequentially** in a single run
- Each profile has:
  - Its own database connection
  - Its own dump file
  - Its own log file
  - Its own post-action execution

This enables:

- One cron job
- Many servers / clients
- Clean separation of concerns

---

## Backup Profile Configuration (`configs/*.env`)

Each profile defines:

- Source database (required)
- Optional target database (restore)
- SSL configuration
- Output directory
- Post-action hook

### Minimal Example (Backup Only)

```env
SRC_HOST=localhost
SRC_PORT=3306
SRC_USER=backup
SRC_PASS=secret
SRC_DB=production_db

DUMP_PATH=/var/backups/mysql
POST_ACTION_SCRIPT=/opt/mysql-backup/post_action_email.sh
```

---

### Backup + Restore Example

```env
TARGET_ENABLE=true

DEST_HOST=10.0.0.20
DEST_PORT=3306
DEST_USER=restore
DEST_PASS=secret
DEST_DB=production_restore
```

---

## Post-Action Hooks

Post-action hooks are executed **after each profile finishes**, regardless of result.

Arguments passed:

- `$1` Status (`SUCCESS` / `ERROR`)
- `$2` Dump file path
- `$3` Log file path
- `$4` Profile name

---

## Email Notification (FINAL DESIGN)

Email delivery uses **msmtp DIRECT (raw SMTP)**.

No `mutt`.  
No `mailx`.  
No interactive composer.

---

## Email Setup (Summary)

1. Install msmtp
2. Configure `/etc/msmtprc`
3. Create `post_action_email.env`
4. Set `POST_ACTION_SCRIPT` in profile
5. Test with `echo "test" | msmtp you@domain`

---

## Cron Example

```cron
0 1 * * * /opt/mysql-backup/mysql_dump_transfer.sh
```

---

## Security Notes

- Never commit `.env` files
- Never commit `post_action_email.env`
- Restrict permissions:
  ```bash
  chmod 600 configs/*.env post_action_email.env
  chmod 700 *.sh
  ```

---

## License

MIT License
