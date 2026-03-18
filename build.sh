#!/usr/bin/env bash
# --------------------------------------------------------------------------
# build.sh — Build the AWS Lambda deployment zip for qlik-chart-export-lambda
#
# Usage:
#   chmod +x build.sh
#   ./build.sh
#
# Output:
#   qlik_chart_export.zip  (ready to upload to AWS Lambda)
#
# Requirements:
#   - Python 3.9+ with pip3
#   - Works on macOS and Linux
#
# IMPORTANT (macOS users):
#   Dependencies are built with --platform manylinux2014_x86_64 so the zip
#   contains Linux-compatible binaries for the Lambda environment.
#   Do NOT skip this flag — packages built natively on macOS will fail on Lambda.
# --------------------------------------------------------------------------

set -euo pipefail

PYTHON_VERSION="3.11"
ZIP_NAME="qlik_chart_export.zip"
PACKAGE_DIR="package"
SOURCE_FILE="qlik_chart_export_lambda.py"

echo "[1/4] Cleaning previous build..."
rm -rf "$PACKAGE_DIR" "$ZIP_NAME"
mkdir "$PACKAGE_DIR"

echo "[2/4] Installing dependencies (Linux wheels for Lambda)..."
pip3 install requests paramiko openpyxl \
  --platform manylinux2014_x86_64 \
  --target "./$PACKAGE_DIR" \
  --only-binary=:all: \
  --implementation cp \
  --python-version "$PYTHON_VERSION" \
  --quiet

echo "[3/4] Copying Lambda function..."
cp "$SOURCE_FILE" "./$PACKAGE_DIR/"

echo "[4/4] Creating zip..."
cd "$PACKAGE_DIR" && zip -r "../$ZIP_NAME" . -x "__pycache__/*" -x "*.pyc" -q && cd ..

echo ""
echo "Build complete!"
echo "  Output: $ZIP_NAME"
echo "  Size:   $(du -sh $ZIP_NAME | cut -f1)"
echo ""
echo "Next step: Upload $ZIP_NAME to AWS Lambda via the AWS Console."
echo "See DEPLOYMENT.md for full instructions."
