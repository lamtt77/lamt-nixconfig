#!/usr/bin/env bash

# Gitea Restore Script
# Usage: sudo ./gitea-restore.sh [zip_file]
# Default zip_file: teadump-daily.zip
# Set FORCE_OVERWRITE=1 to skip confirmation prompt

set -e  # Exit on any error

# Default values
ZIP_FILE="${1:-teadump-daily.zip}"
GITEA_BASE="/var/lib/gitea"
DATABASE_PATH="${GITEA_BASE}/data/gitea.db"  # Adjust if using a different DB path

# Derive extract directory from zip file name (remove .zip extension)
if [[ "$ZIP_FILE" != *.zip ]]; then
    echo "Error: Input file must be a .zip file."
    exit 1
fi
EXTRACT_DIR="${ZIP_FILE%.zip}"

# Check if zip file exists
if [[ ! -f "$ZIP_FILE" ]]; then
    echo "Error: Zip file '$ZIP_FILE' not found."
    exit 1
fi

# Create extract directory
mkdir -p "$EXTRACT_DIR"

# Unzip the file into the extract directory
echo "Unzipping $ZIP_FILE into $EXTRACT_DIR..."
unzip "$ZIP_FILE" -d "$EXTRACT_DIR"

# Check if extraction succeeded (look for expected subdirs/files)
if [[ ! -d "$EXTRACT_DIR" ]] || [[ ! -f "$EXTRACT_DIR/gitea-db.sql" && ! -d "$EXTRACT_DIR/data" ]]; then
    echo "Error: Extraction failed or expected files not found in $EXTRACT_DIR."
    exit 1
fi

# Confirm overwrite
if [[ -z "$FORCE_OVERWRITE" ]]; then
    read -p "This will overwrite existing Gitea files. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

cd "$EXTRACT_DIR"

# Move directories (skip app.ini as not needed)
echo "Moving Gitea data..."
# mv app.ini /etc/gitea/conf/app.ini
[[ -d custom ]] && rsync -a custom/ "${GITEA_BASE}/custom/"
[[ -d data ]] && rsync -a data/ "${GITEA_BASE}/data/"
[[ -d log ]] && rsync -a log/ "${GITEA_BASE}/log/"
[[ -d repos ]] && rsync -a repos/ "${GITEA_BASE}/repositories"

# Set ownership
echo "Setting ownership..."
chown -R git:gitea "${GITEA_BASE}"

# Restore database, not-needed as the backup data dir contaied gitea.db
# if [[ -f gitea-db.sql ]]; then
#     echo "Restoring database..."
#     sudo -u git sqlite3 "${GITEA_BASE}/data/gitea.db" < gitea-db.sql
# else
#     echo "Warning: gitea-db.sql not found in $EXTRACT_DIR"
# fi

echo "Gitea restore completed successfully."
