# qlik-chart-export-lambda

An AWS Lambda function that exports chart data from **Qlik Cloud** (XLSX or CSV) and optionally uploads the file to an **SFTP server**. Supports **Slack notifications** for success and failure.

---

## Features

- Export any Qlik Cloud chart/table as **XLSX** and if selected then transform it on **CSV**
- Optionally apply a **temporary bookmark** (pre-filtered selections)
- Upload the exported file to an **SFTP server** (auto-creates remote directories)
- Send **Slack notifications** on success or failure
- Schedule via **AWS EventBridge** (e.g., weekly on Monday at 6 AM UTC)
- All config via **environment variables** — no hardcoded secrets

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Environment Variables](#2-environment-variables)
3. [Build the Deployment Package](#3-build-the-deployment-package)
4. [Create the Lambda Function](#4-create-the-lambda-function)
5. [Upload the Zip](#5-upload-the-zip)
6. [Set the Handler](#6-set-the-handler)
7. [Configure Memory and Timeout](#7-configure-memory-and-timeout)
8. [Set Environment Variables in Lambda](#8-set-environment-variables-in-lambda)
9. [Test the Function](#9-test-the-function)
10. [Set Up SFTP Upload](#10-set-up-sftp-upload)
11. [Set Up Slack Notifications](#11-set-up-slack-notifications)
12. [Schedule Weekly Execution](#12-schedule-weekly-execution)
13. [Re-deploying After Code Changes](#13-re-deploying-after-code-changes)
14. [How It Works](#14-how-it-works)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Prerequisites

- **Python 3.9+** installed locally (`python3 --version`)
- **pip3** available (`pip3 --version` — on macOS it may show as `pip3` not `pip`)
- **AWS account** with permissions to create Lambda functions
- **Qlik Cloud tenant** with an active API key
- (Optional) SFTP server credentials
- (Optional) Slack workspace with Incoming Webhooks enabled

---

## 2. Environment Variables

### Required — Qlik Cloud

| Variable | Description | Example |
|---|---|---|
| `QLIK_BASE_URL` | Your Qlik Cloud tenant URL | `https://your-tenant.eu.qlikcloud.com` |
| `QLIK_API_KEY` | API key from Qlik Cloud profile settings | `eyJh...` |
| `QLIK_APP_ID` | App GUID (from the app URL in your browser) | `c3e242...` |
| `QLIK_CHART_ID` | Chart/table object ID (right-click chart → Edit) | `tPZH` |

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
| `SFTP_REMOTE_PATH` | — | Remote path. Trailing `/` = filename auto-appended |

> **Note:** Linux SFTP paths are case-sensitive. `/Import/` ≠ `/import/` — match exactly what exists on the server.

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

## 3. Build the Deployment Package

AWS Lambda runs on **Linux (x86_64)**. If you build on macOS, native Python packages will contain macOS binaries that crash on Lambda. You must force Linux-compatible wheels.

```bash
# Run from the folder containing qlik_chart_export_lambda.py
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

> **Why `--platform manylinux2014_x86_64`?**  
> This forces pip to download pre-built Linux wheels instead of compiling from source on your Mac. Without this flag, `paramiko`'s cryptography library will contain macOS `.dylib` binaries that cannot run on Lambda's Linux environment. You will see an error like `paramiko is required for SFTP upload` even though it was installed.

> **macOS note:** Use `pip3` not `pip` — macOS does not ship with a `pip` command.

---

## 4. Create the Lambda Function

1. Open [AWS Console → Lambda](https://console.aws.amazon.com/lambda)
2. Click **Create function**
3. Select **Author from scratch**
4. Fill in:
   - **Function name**: `qlik-chart-export` (or any name you prefer)
   - **Runtime**: Python 3.11 (or 3.12)
   - **Architecture**: x86_64
5. Leave permissions as default (creates a basic execution role)
6. Click **Create function**

---

## 5. Upload the Zip

1. In your new Lambda function, go to the **Code** tab
2. Click **Upload from** → **.zip file**
3. Select `qlik_chart_export.zip`
4. Click **Save**

You should see `qlik_chart_export_lambda.py` appear in the code browser.

---

## 6. Set the Handler

> **Common mistake:** If you skip this step you will get `No module named 'lambda_function'`.

1. In the **Code** tab, scroll down to **Runtime settings**
2. Click **Edit**
3. Change the **Handler** from the AWS default:
   ```
   lambda_function.lambda_handler
   ```
   to:
   ```
   qlik_chart_export_lambda.lambda_handler
   ```
4. Click **Save**

The format is always `filename_without_extension.function_name`.

---

## 7. Configure Memory and Timeout

1. Go to **Configuration** → **General configuration** → **Edit**
2. Set:
   - **Memory**: `256 MB`
   - **Timeout**: `10 min 0 sec`
3. Click **Save**

> Chart exports can take 30–120 seconds depending on data volume. The default 3-second timeout will always fail.

---

## 8. Set Environment Variables in Lambda

1. Go to **Configuration** → **Environment variables** → **Edit**
2. Add your variables (see [Section 2](#2-environment-variables) for the full list)
3. Click **Save**

Minimum required:

| Key | Value |
|---|---|
| `QLIK_BASE_URL` | `https://your-tenant.eu.qlikcloud.com` |
| `QLIK_API_KEY` | Your API key |
| `QLIK_APP_ID` | Your app GUID |
| `QLIK_CHART_ID` | Your chart object ID |

---

## 9. Test the Function

1. Click the **Test** tab
2. Create a new test event named `empty-test` with body `{}`
3. Click **Test**

Expected successful response:

```json
{
  "ok": true,
  "request_id": "abc123...",
  "status": "done",
  "local_file": "/tmp/qlik-tPZH-20260318-060000.xlsx",
  "file_name": "qlik-tPZH-20260318-060000.xlsx",
  "sftp": {
    "enabled": true,
    "uploaded": true,
    "host": "sftp.yourserver.com",
    "port": 22,
    "remote_path": "/Import/qlik-tPZH-20260318-060000.xlsx"
  }
}
```

You can override any config per-invocation in the test event:

```json
{
  "output_type": "csv",
  "sftp": {
    "enabled": false
  }
}
```

---

## 10. Set Up SFTP Upload

Add these env vars in Lambda (see step 8):

| Key | Value |
|---|---|
| `SFTP_ENABLED` | `true` |
| `SFTP_HOST` | `sftp.yourserver.com` |
| `SFTP_PORT` | `22` |
| `SFTP_USERNAME` | your SFTP username |
| `SFTP_PASSWORD` | your SFTP password |
| `SFTP_REMOTE_PATH` | `/Import/` (trailing slash = auto-append filename) |

The function automatically creates any missing directories on the SFTP server.

### CSV output

Set `OUTPUT_TYPE=csv` to get a CSV file. The Qlik API only produces XLSX, so the function:
1. Requests XLSX from Qlik
2. Converts locally using `openpyxl`
3. Uploads the CSV to SFTP

---

## 11. Set Up Slack Notifications

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **Create New App** → **From scratch**
3. Name it (e.g., `Qlik Export Bot`) and choose your workspace
4. In the left menu, click **Incoming Webhooks**
5. Toggle **Activate Incoming Webhooks** to ON
6. Click **Add New Webhook to Workspace** → select your channel → **Allow**
7. Copy the **Webhook URL** (starts with `https://hooks.slack.com/services/...`)
8. Add it to Lambda env vars as `SLACK_WEBHOOK_URL`

You will receive:
- ✅ Success message with filename and SFTP path
- ❌ Failure message with the error details

If `SLACK_WEBHOOK_URL` is not set, notifications are silently skipped — the export still works.

---

## 12. Schedule Weekly Execution

1. In your Lambda function → **Configuration** → **Triggers** → **Add trigger**
2. Select **EventBridge (CloudWatch Events)**
3. Select **Create a new rule** → Rule type: **Schedule expression**
4. Enter your cron and click **Add**

| Goal | Expression |
|---|---|
| Every Monday at 6:00 AM UTC | `cron(0 6 ? * MON *)` |
| Every Monday at 8:00 AM UTC | `cron(0 8 ? * MON *)` |
| Every day at 7:00 AM UTC | `cron(0 7 * * ? *)` |
| First of every month at midnight | `cron(0 0 1 * ? *)` |

> **All cron times are UTC.** Adjust for your timezone:  
> - UTC+1 (CET winter): subtract 1 hour from your desired local time  
> - UTC+2 (CEST summer): subtract 2 hours

---

## 13. Re-deploying After Code Changes

Whenever you update `qlik_chart_export_lambda.py`, rebuild and re-upload.

**Via AWS Console:**

```bash
rm -rf package qlik_chart_export.zip && mkdir package
pip3 install requests paramiko openpyxl \
  --platform manylinux2014_x86_64 \
  --target ./package \
  --only-binary=:all: \
  --implementation cp \
  --python-version 3.11
cp qlik_chart_export_lambda.py ./package/
cd package && zip -r ../qlik_chart_export.zip . && cd ..
```

Then upload `qlik_chart_export.zip` to Lambda via **Code → Upload from → .zip file**.

**Via AWS CLI:**

```bash
aws lambda update-function-code \
  --function-name qlik-chart-export \
  --zip-file fileb://qlik_chart_export.zip
```

---

## 14. How It Works

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

> The Qlik `sense-data-1.0` Reports API always produces XLSX. CSV requests are fulfilled by downloading XLSX and converting locally with `openpyxl`.

---

## 15. Troubleshooting

### `No module named 'lambda_function'`

**Cause:** The default Lambda handler name doesn't match the filename.  
**Fix:** In Runtime settings, change handler from `lambda_function.lambda_handler` to `qlik_chart_export_lambda.lambda_handler`

---

### `paramiko is required for SFTP upload`

**Cause:** The zip was built on macOS — it contains macOS binaries that don't run on Lambda's Linux.  
**Fix:** Rebuild the zip using the commands in [Section 3](#3-build-the-deployment-package) — the `--platform manylinux2014_x86_64` flag is required.

---

### File uploaded to SFTP but not visible

**Cause:** Linux SFTP paths are case-sensitive. `/Import/` and `/import/` are different directories.  
**Fix:** Check the exact path on the SFTP server and update `SFTP_REMOTE_PATH` to match exactly.

---

### `Missing required environment variable: QLIK_BASE_URL`

**Cause:** Env var not set or a typo in the name.  
**Fix:** Go to Configuration → Environment variables, verify all required vars are set, and click Save.

---

### Export times out

**Cause:** Lambda default timeout is 3 seconds; chart export can take 30–120 seconds.  
**Fix:** Set Lambda timeout to 10 minutes (Configuration → General configuration).

---

### `pip` not found (macOS)

**Cause:** macOS ships with `pip3`, not `pip`.  
**Fix:** Use `pip3` in all commands.

---

## License

MIT
