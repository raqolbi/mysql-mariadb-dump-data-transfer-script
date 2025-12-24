# MySQL / MariaDB Dump & Optional Transfer Script (Bash)

A Bash script to perform **MySQL/MariaDB database backups (dump)** with advanced features such as automatic timestamped filenames, per-run logging, optional SSL connections, optional restore to a target database, and post-action hooks after execution.

This script is designed as a **scriptable, production-friendly alternative to GUI automation tools** (e.g. Navicat), suitable for servers and cron jobs.

---

## Key Features

- Database dump with filename format:
  ```
  [database_name]_[YYYY-MM-DD_HH.MM.SS].sql
  ```
- Automatic log file per execution:
  ```
  [database_name]_[YYYY-MM-DD_HH.MM.SS].log
  ```
- Supports MySQL and MariaDB
- Optional **SSL configuration** (source & target)
- Optional restore to a target database
- Post-action hook (email, webhook, upload, etc.)
- Cron-safe (non-interactive execution)

---

## File Structure

```
.
├── mysql_dump_transfer.sh
├── post_action.sh        # optional
└── README.md
```

---

## Requirements

- Bash
- MySQL / MariaDB client tools
  ```bash
  mysql --version
  mysqldump --version
  ```
- Database user privileges:
  - SELECT
  - TRIGGER, EVENT, ROUTINE (if used)
  - LOCK TABLES (optional)

---

## Configuration

Edit `mysql_dump_transfer.sh` and adjust the **CONFIGURATION** section.

---

### Source Database (Required)

```bash
SRC_HOST="localhost"
SRC_PORT="3306"
SRC_USER="root"
SRC_PASS="password"
SRC_DB="database_name"
```

---

### Source SSL (Optional)

```bash
SRC_SSL_ENABLE=true
SRC_SSL_CA="/path/ssl/ca.pem"
SRC_SSL_CERT="/path/ssl/client-cert.pem"
SRC_SSL_KEY="/path/ssl/client-key.pem"
```

If `SRC_SSL_ENABLE=false`, a non-SSL connection will be used.

---

### Target Database (Optional)

Enable this if you want the dump to be automatically restored to another database.

```bash
TARGET_ENABLE=true
DEST_HOST="localhost"
DEST_PORT="3306"
DEST_USER="root"
DEST_PASS="password"
DEST_DB="target_database"
```

To store dump files only (no restore):

```bash
TARGET_ENABLE=false
```

---

### Target SSL (Optional)

```bash
DEST_SSL_ENABLE=true
DEST_SSL_CA="/path/ssl/ca.pem"
DEST_SSL_CERT="/path/ssl/client-cert.pem"
DEST_SSL_KEY="/path/ssl/client-key.pem"
```

---

### Backup Output Directory

```bash
DUMP_PATH="/var/backups/mysql"
```

The directory will be created automatically if it does not exist.

---

### Post Action Script (Optional)

Script executed after the process finishes (success or error).

```bash
POST_ACTION_SCRIPT="/path/post_action.sh"
```

If empty, no additional action will be executed.

---

## How to Run

### Run Manually

```bash
chmod +x mysql_dump_transfer.sh
./mysql_dump_transfer.sh
```

---

### Run with Cron

Example: run daily at 01:00

```bash
crontab -e
```

```cron
0 1 * * * /path/mysql_dump_transfer.sh
```

---

## Example Output

```
/var/backups/mysql/
├── salesdb_2025-12-24_12.51.20.sql
├── salesdb_2025-12-24_12.51.20.log
```

---

## Logging & Error Handling

- All errors are written to the `.log` file
- If dump or restore fails:
  - The script exits with a non-zero code
  - The post-action hook is executed with `ERROR` status

---

## Post Action Hook

### Arguments Passed

| Argument | Description |
|--------|-------------|
| `$1` | Status (`SUCCESS` or `ERROR`) |
| `$2` | Dump file path |
| `$3` | Log file path |

### Example `post_action.sh`

```bash
#!/usr/bin/env bash

STATUS="$1"
DUMP_FILE="$2"
LOG_FILE="$3"

if [[ "$STATUS" == "SUCCESS" ]]; then
  echo "Backup successful: $DUMP_FILE"
else
  echo "Backup failed. Check log: $LOG_FILE"
fi
```

Enable execution:
```bash
chmod +x post_action.sh
```

---

## Security Notes

- Do not commit database passwords to public repositories
- Prefer `.my.cnf` or environment variables in production
- Restrict backup file permissions:
  ```bash
  chmod 600 *.sql *.log
  ```

---

## Possible Enhancements

This script can be extended to support:
- Automatic compression (`.sql.gz`)
- Backup retention policy
- Upload to S3 / MinIO
- Incremental backups
- Alerting (Email / Telegram / Slack)

---

## License

MIT License

---

## Contributing

Pull requests and improvements are welcome.
