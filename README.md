# qlik-chart-export-lambda

An AWS Lambda function that exports chart data from **Qlik Cloud** (XLSX or CSV) and optionally uploads the file to an **SFTP server**. Supports **Slack notifications** for success and failure.

---

## Features

- Export any Qlik Cloud chart/table as **XLSX** or **CSV**
- Optionally apply a **temporary bookmark** (pre-filtered selections)
- Upload the exported file to an **SFTP server** (auto-creates remote directories)
- Send **Slack notifications** on success or failure
- Schedule via **AWS EventBridge** (e.g., weekly on Monday at 6 AM UTC)
- All config via **environment variables** — no hardcoded secrets

---

## Prerequisites

- Python 3.9+ (for local packaging; Lambda runtime can be 3.11+)
- AWS account with Lambda access
- Qlik Cloud tenant with an API key
- (Optional) SFTP server credentials
- (Optional) Slack Incoming Webhook URL

---

## Environment Variables

### Required — Qlik Cloud

| Variable | Description | Example |
|---|---|---|
| `QLIK_BASE_URL` | Your Qlik Cloud tenant URL | `https://your-tenant.eu.qlikcloud.com` |
| `QLIK_API_KEY` | API key from Qlik Cloud profile settings | `eyJh...` |
| `QLIK_APP_ID` | App GUID (from the app URL) | `c3e242...` |
| `QLIK_CHART_ID` | Chart/table object ID | `tPZH` |

### Optional — Output

| Variable | Default | Description |
|---|---|---|
| `OUTPUT_TYPE` | `xlsx` | Output format: `xlsx` or `csv` |
| `CSV_SHEET_NAME` | first sheet | Sheet to read when converting XLSX → CSV |
| `QLIK_TEMPORARY_BOOKMARK_ID` | — | Apply a bookmark before exporting (pre-filtered data) |

### Optional — SFTP

| Variable | Default | Description |
|---|---|---|
| `SFTP_ENABLED` | `false` | Set to `true` to enable SFTP upload |
| `SFTP_HOST` | — | SFTP server hostname or IP |
| `SFTP_PORT` | `22` | SFTP port |
| `SFTP_USERNAME` | — | SFTP username |
| `SFTP_PASSWORD` | — | SFTP password |
| `SFTP_REMOTE_PATH` | — | Remote path. If ends with `/`, filename is appended automatically |

> **Note:** Linux SFTP paths are case-sensitive. `/Import/` ≠ `/import/`

### Optional — Slack

| Variable | Description |
|---|---|
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL. If not set, notifications are silently skipped |

### Optional — Tuning

| Variable | Default | Description |
|---|---|---|
| `HTTP_TIMEOUT_SECONDS` | `30` | Timeout for HTTP requests |
| `POLL_INTERVAL_SECONDS` | `2` | How often to poll Qlik for export status |
| `POLL_TIMEOUT_SECONDS` | `600` | Maximum wait time for export to complete |

---

## Deployment

### 1. Build the deployment package

> **Important for macOS users:** You must use `--platform manylinux2014_x86_64` to build Linux-compatible wheels. Packages built natively on macOS will fail on Lambda.

```bash
cd ~/Downloads   # or wherever your project folder is
rm -rf package qlik_chart_export.zip
mkdir package

pip3 install requests paramiko openpyxl \
  --platform manylinux2014_x86_64 \
  --target ./package \
  --only-binary=:all: \
  --implementation cp \
  --python-version 3.11

cp qlik_chart_export_lambda.py ./package/
cd package && zip -r ../qlik_chart_export.zip . && cd ..
```

### 2. Create the Lambda function

1. Go to **AWS Console → Lambda → Create function**
2. Choose **Author from scratch**
3. Runtime: **Python 3.11** (or 3.12/3.14)
4. Architecture: **x86_64**
5. Click **Create function**

### 3. Upload the zip

1. In your Lambda function → **Code** tab
2. Click **Upload from → .zip file**
3. Upload `qlik_chart_export.zip`

### 4. Set the handler

In **Runtime settings**, set the handler to:
```
qlik_chart_export_lambda.lambda_handler
```

### 5. Set environment variables

In **Configuration → Environment variables**, add all required variables (see table above).

### 6. Configure timeout and memory

In **Configuration → General configuration**:
- **Memory**: 256 MB
- **Timeout**: 10 minutes (charts can take a while to export)

### 7. Test the function

Create a test event with an empty JSON body `{}` — the function will read all config from environment variables:

```json
{}
```

Or override specific values per-invocation:

```json
{
  "output_type": "csv",
  "sftp": {
    "enabled": true,
    "host": "sftp.example.com",
    "username": "myuser",
    "password": "mypassword",
    "remote_path": "/Import/"
  }
}
```

---

## Scheduling (Weekly Export)

1. Go to **Lambda → your function → Configuration → Triggers → Add trigger**
2. Choose **EventBridge (CloudWatch Events)**
3. Create a new rule with a **Schedule expression**

Examples (all times are **UTC**):

| Schedule | Cron expression |
|---|---|
| Every Monday at 6:00 AM UTC | `cron(0 6 ? * MON *)` |
| Every day at 8:00 AM UTC | `cron(0 8 * * ? *)` |
| First day of month at midnight | `cron(0 0 1 * ? *)` |

---

## Slack Notifications

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → Create App → **Incoming Webhooks**
2. Activate Incoming Webhooks and add to your workspace/channel
3. Copy the Webhook URL and add it as the `SLACK_WEBHOOK_URL` Lambda environment variable

You will receive:
- ✅ Success message with filename and SFTP path
- ❌ Failure message with the error details

---

## How It Works

```
lambda_handler(event)
    └─ _run(event)
          ├─ create_export_payload()   Build Qlik API request
          ├─ request_export()          POST /api/v1/reports
          ├─ poll_until_done()         Poll status until "done"
          ├─ download_file()           Download XLSX to /tmp
          ├─ convert_xlsx_to_csv()     (optional) Convert to CSV
          ├─ upload_sftp()             (optional) Upload to SFTP
          └─ send_slack_notification() (optional) Notify Slack
```

> **Note:** The Qlik `sense-data-1.0` Reports API always produces XLSX. If you request CSV, the function downloads XLSX and converts it locally using `openpyxl`.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `No module named 'lambda_function'` | Wrong handler name | Set handler to `qlik_chart_export_lambda.lambda_handler` |
| `paramiko is required for SFTP upload` | macOS-built package | Rebuild with `--platform manylinux2014_x86_64 --only-binary=:all:` |
| File not visible on SFTP | Case sensitivity | Linux paths are case-sensitive: `/Import/` ≠ `/import/` |
| `Missing required environment variable` | Env var not set | Check Lambda Configuration → Environment variables |
| Export times out | Chart is large | Increase `POLL_TIMEOUT_SECONDS` or Lambda timeout |

---

## License

MIT
