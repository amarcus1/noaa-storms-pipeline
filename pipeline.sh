#!/usr/bin/env bash
#
# pipeline.sh — Download a year of NOAA Storm Events, convert to GeoParquet.
#
# Usage:   ./pipeline.sh [YEAR]
# Example: ./pipeline.sh 2024
#
# Requires: bash, curl, gunzip, ogr2ogr (GDAL >= 3.5)
#

set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

# Year to pull. Override by passing as the first argument.
YEAR="${1:-2024}"

# NOAA file naming pattern. The "c{CREATED_DATE}" portion changes when NOAA
# republishes a year's data (seen for 1984, 2017, 2022, 2024-2026 in the
# current listing at https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles).
# This mapping is a hardcoded snapshot, not dynamically fetched -- if NOAA
# republishes a year not listed here, the download will 404 until this is updated.
if   [[ "$YEAR" -eq 1984 ]]; then CREATED_DATE="20260527"
elif [[ "$YEAR" -eq 2017 ]]; then CREATED_DATE="20260519"
elif [[ "$YEAR" -eq 2022 ]]; then CREATED_DATE="20260625"
elif [[ "$YEAR" -eq 2024 ]]; then CREATED_DATE="20260728"
elif [[ "$YEAR" -eq 2025 ]]; then CREATED_DATE="20260819"
elif [[ "$YEAR" -eq 2026 ]]; then CREATED_DATE="20260918"
else                              CREATED_DATE="20260323"
fi


BASE_URL="https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles"
FILE_NAME="StormEvents_details-ftp_v1.0_d${YEAR}_c${CREATED_DATE}.csv.gz"
URL="${BASE_URL}/${FILE_NAME}"

RAW_DIR="data/raw"
PROCESSED_DIR="data/processed"
RAW_GZ="${RAW_DIR}/${FILE_NAME}"
RAW_CSV="${RAW_DIR}/${FILE_NAME%.gz}"
OUT_PARQUET="${PROCESSED_DIR}/storms_${YEAR}.parquet"

# -----------------------------------------------------------------------------
# Step 1: Set up directories
# -----------------------------------------------------------------------------

echo "[1/4] Setting up directories"
# Use mkdir -p to create RAW_DIR and PROCESSED_DIR. Both should be
# safe to call even if the directories already exist.
mkdir -p "$RAW_DIR"
mkdir -p "$PROCESSED_DIR"

# -----------------------------------------------------------------------------
# Step 2: Download the raw file
# -----------------------------------------------------------------------------

echo "[2/4] Downloading ${FILE_NAME}"
# Use curl to download URL into RAW_GZ. Suggested flags:
#   -L       follow redirects
#   -o       write to a specific output file path
#   --fail   exit non-zero on HTTP errors (4xx/5xx)
#
# Skip the download if the file already exists (idempotency).

if [[ -f "$RAW_GZ" ]]; then
    echo "  ${RAW_GZ} already exists, skipping download"
else
    curl -L --fail -o "$RAW_GZ" "$URL"
fi

# -----------------------------------------------------------------------------
# Step 3: Decompress
# -----------------------------------------------------------------------------

# Use gunzip to decompress RAW_GZ into RAW_CSV.
# The -k flag keeps the original .gz so the pipeline can rerun.
# Skip this step if RAW_CSV already exists.
echo "[3/4] Decompressing ${FILE_NAME}"
if [[ -f "$RAW_CSV" ]]; then
    echo "  ${RAW_CSV} already exists, skipping decompression"
else
    gunzip -k "$RAW_GZ"
fi


# -----------------------------------------------------------------------------
# Step 4: Convert CSV to GeoParquet
# -----------------------------------------------------------------------------

echo "[4/4] Converting to GeoParquet"
# Use ogr2ogr to convert RAW_CSV into a GeoParquet file at OUT_PARQUET.
#
# The CSV uses BEGIN_LON / BEGIN_LAT for the storm start point. ogr2ogr can
# pick those up if you tell it the column names with -oo:
#
#   -oo X_POSSIBLE_NAMES=BEGIN_LON
#   -oo Y_POSSIBLE_NAMES=BEGIN_LAT
#
# The data is in WGS 84 (EPSG:4326). Set that explicitly with -a_srs.
#
# Use -f Parquet for the output format.
#
# Tip: ask your AI pair (see R1.3 prompts 4 and 6) for the exact ogr2ogr
# command, then verify the flags against `ogr2ogr --help` before running.
ogr2ogr \
    -f Parquet \
    -oo X_POSSIBLE_NAMES=BEGIN_LON \
    -oo Y_POSSIBLE_NAMES=BEGIN_LAT \
    -a_srs EPSG:4326 \
    "$OUT_PARQUET" \
    "$RAW_CSV"


echo "Done. Output: ${OUT_PARQUET}"
echo "Open it in DuckDB:"
echo "  duckdb -c \"INSTALL spatial; LOAD spatial; SELECT COUNT(*) FROM read_parquet('${OUT_PARQUET}');\""
