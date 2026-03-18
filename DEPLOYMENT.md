# Complete Deployment Guide

This is the full step-by-step guide to deploy `qlik_chart_export_lambda.py` as an AWS Lambda function, including real troubleshooting lessons learned.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Build the Deployment Package](#2-build-the-deployment-package)
3. [Create the Lambda Function](#3-create-the-lambda-function)
4. [Upload the Zip](#4-upload-the-zip)
5. [Set the Handler](#5-set-the-handler)
6. [Configure Memory and Timeout](#6-configure-memory-and-timeout)
7. [Set Environment Variables](#7-set-environment-variables)
8. [Test the Function](#8-test-the-function)
9. [Set Up SFTP Upload](#9-set-up-sftp-upload)
10. [Set Up Slack Notifications](#10-set-up-slack-notifications)
11. [Schedule Weekly Execution](#11-schedule-weekly-execution)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

- **Python 3.9+** installed locally (`python3 --version`)
- **pip3** available (`pip3 --version` — on macOS it may show as `pip3` not `pip`)
- **AWS account** with permissions to create Lambda functions
- **Qlik Cloud tenant** with an active API key
- (Optional) SFTP server credentials
- (Optional) Slack workspace with Incoming Webhooks enabled

---

## 2. Build the Deployment Package

AWS Lambda runs on **Linux (x86_64)**. If you build on macOS, native Python packages will contain macOS binaries that crash on Lambda. You must force Linux-compatible wheels.

### Automated (recommended)

```bash
chmod +x build.sh
./build.sh
```

This produces `qlik_chart_export.zip` ready to upload.

### Manual steps

```bash
# Start from the project folder
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

---

## 3. Create the Lambda Function

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

## 4. Upload the Zip

1. In your new Lambda function, go to the **Code** tab
2. Click **Upload from** → **.zip file**
3. Select `qlik_chart_export.zip`
4. Click **Save**

You should see the file `qlik_chart_export_lambda.py` appear in the code browser.

---

## 5. Set the Handler

> This is a common mistake. If you skip this step, you will get:  
> `No module named 'lambda_function'`

1. In the **Code** tab, scroll down to **Runtime settings**
2. Click **Edit**
3. Change the **Handler** from the default `lambda_function.lambda_handler` to:
   ```
   qlik_chart_export_lambda.lambda_handler
   ```
4. Click **Save**

The handler format is `filename_without_extension.function_name`.

---

## 6. Configure Memory and Timeout

1. Go to **Configuration** → **General configuration** → **Edit**
2. Set:
   - **Memory**: `256 MB`
   - **Timeout**: `10 min 0 sec`
3. Click **Save**

Chart exports can take 30–60 seconds depending on data volume. The default 3-second timeout will always fail.

---

## 7. Set Environment Variables

1. Go to **Configuration** → **Environment variables** → **Edit**
2. Add the following variables:

### Required — Qlik Cloud

| Key | Value |
|---|---|
| `QLIK_BASE_URL` | `https://your-tenant.eu.qlikcloud.com` |
| `QLIK_API_KEY` | Your API key from Qlik Cloud profile settings |
| `QLIK_APP_ID` | The app GUID (from the app URL in your browser) |
| `QLIK_CHART_ID` | The chart/table object ID (right-click chart → Edit → see object ID) |

### Optional — SFTP

| Key | Value |
|---|---|
| `SFTP_ENABLED` | `true` |
| `SFTP_HOST` | `sftp.yourserver.com` |
| `SFTP_PORT` | `22` |
| `SFTP_USERNAME` | your SFTP username |
| `SFTP_PASSWORD` | your SFTP password |
| `SFTP_REMOTE_PATH` | `/Import/` (trailing slash = auto-append filename) |

> **Case sensitivity warning:** Linux SFTP paths are case-sensitive.  
> `/Import/` and `/import/` are different directories. Match exactly what exists on the server.

### Optional — Output format

| Key | Value |
|---|---|
| `OUTPUT_TYPE` | `xlsx` (default) or `csv` |

### Optional — Slack

| Key | Value |
|---|---|
| `SLACK_WEBHOOK_URL` | Your Slack Incoming Webhook URL |

3. Click **Save**

---

## 8. Test the Function

1. Click the **Test** tab
2. Create a new test event named `empty-test` with body:
   ```json
   {}
   ```
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

You can also override any config per-invocation in the test event:

```json
{
  "output_type": "csv",
  "sftp": {
    "enabled": false
  }
}
```

---

## 9. Set Up SFTP Upload

Ensure these env vars are set (see step 7):
- `SFTP_ENABLED=true`
- `SFTP_HOST`, `SFTP_PORT`, `SFTP_USERNAME`, `SFTP_PASSWORD`
- `SFTP_REMOTE_PATH` — use a trailing `/` to auto-append the filename, or specify the full path including filename

The function will automatically create any missing directories on the SFTP server.

### CSV output

Set `OUTPUT_TYPE=csv` to get a CSV instead of XLSX. The function:
1. Requests XLSX from Qlik (the API only produces XLSX)
2. Converts locally using `openpyxl`
3. Uploads the CSV to SFTP

---

## 10. Set Up Slack Notifications

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **Create New App** → **From scratch**
3. Name it (e.g., `Qlik Export Bot`) and choose your workspace
4. In the left menu, click **Incoming Webhooks**
5. Toggle **Activate Incoming Webhooks** to ON
6. Click **Add New Webhook to Workspace**
7. Select the channel to post to → **Allow**
8. Copy the **Webhook URL** (starts with `https://hooks.slack.com/services/...`)
9. Add it to Lambda env vars as `SLACK_WEBHOOK_URL`

You will now receive:
- ✅ `Qlik chart export succeeded` with filename and SFTP path
- ❌ `Qlik chart export FAILED` with the error message

If `SLACK_WEBHOOK_URL` is not set, notifications are silently skipped — the export still works.

---

## 11. Schedule Weekly Execution

1. In your Lambda function → **Configuration** → **Triggers** → **Add trigger**
2. Select **EventBridge (CloudWatch Events)**
3. Select **Create a new rule**
4. Rule type: **Schedule expression**
5. Enter your cron:

| Goal | Expression |
|---|---|
| Every Monday at 6:00 AM UTC | `cron(0 6 ? * MON *)` |
| Every Monday at 8:00 AM UTC | `cron(0 8 ? * MON *)` |
| Every day at 7:00 AM UTC | `cron(0 7 * * ? *)` |
| First of every month at midnight | `cron(0 0 1 * ? *)` |

> **All cron times are UTC.** Adjust for your timezone:  
> - UTC+1 (CET): subtract 1 hour from your desired local time  
> - UTC+2 (CEST/summer): subtract 2 hours

6. Click **Add**

---

## 12. Troubleshooting

### `No module named 'lambda_function'`

**Cause:** The default Lambda handler name doesn't match the filename.  
**Fix:** In Runtime settings, change handler to `qlik_chart_export_lambda.lambda_handler`

---

### `paramiko is required for SFTP upload`

**Cause:** The zip was built on macOS — it contains macOS `.so` / `.dylib` binaries that don't run on Lambda's Linux.

**Fix:** Rebuild the zip with Linux platform flags:

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

Then re-upload the zip to Lambda.

---

### File uploaded to SFTP but not visible

**Cause:** Linux SFTP paths are case-sensitive. If the directory is `/Import/` but you set `/import/`, the file goes to a different (hidden) location.  
**Fix:** Check the exact path on the SFTP server and update `SFTP_REMOTE_PATH` env var to match exactly.

---

### `Missing required environment variable: QLIK_BASE_URL`

**Cause:** Env vars not saved or typo in variable name.  
**Fix:** Go to Configuration → Environment variables and verify all required vars are set and saved.

---

### Export times out

**Cause:** Lambda default timeout is 3 seconds; chart export can take 30–120 seconds.  
**Fix:** Set Lambda timeout to 10 minutes (Configuration → General configuration).

---

### `pip` not found (macOS)

**Cause:** macOS ships with `pip3`, not `pip`.  
**Fix:** Use `pip3` instead of `pip` in all commands.

---

## Re-deploying After Code Changes

Whenever you update `qlik_chart_export_lambda.py`, rebuild and re-upload:

```bash
./build.sh
# Then upload qlik_chart_export.zip to Lambda via AWS Console
```

Or via AWS CLI:

```bash
./build.sh
aws lambda update-function-code \
  --function-name qlik-chart-export \
  --zip-file fileb://qlik_chart_export.zip
```
