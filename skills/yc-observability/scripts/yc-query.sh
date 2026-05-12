#!/usr/bin/env bash
# yc-query.sh — run a SeleQL query against the YC Monitoring data API.
#
# Exit codes:
#   0  success, at least one non-NaN value returned
#   1  bad arguments
#   2  API call failed (non-2xx)
#   3  response has no metrics
#   4  response has metrics but all values are NaN
#
# Requires: yc (Yandex Cloud CLI), curl, jq.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: yc-query.sh --folder-id <id> --query <seleql> [--window <duration>]

Options:
  --folder-id <id>     YC folder ID containing the metrics (required).
  --query <seleql>     The SeleQL query to run (required). Quote it.
  --window <duration>  How far back to look. Default: 1h. Accepts Nm/Nh/Nd.
  --raw                Print full API response (default: print summary).
  -h, --help           This message.

Examples:
  yc-query.sh --folder-id b1g... --query 'series_sum(non_negative_derivative("luvento_back.http_requests_total"{service="custom"}))'
  yc-query.sh --folder-id b1g... --query '...' --window 24h --raw
EOF
}

# --- arg parsing ---
FOLDER_ID=""
QUERY=""
WINDOW="1h"
RAW=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --folder-id) FOLDER_ID="$2"; shift 2 ;;
        --query)     QUERY="$2";     shift 2 ;;
        --window)    WINDOW="$2";    shift 2 ;;
        --raw)       RAW=1;          shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ -z "$FOLDER_ID" || -z "$QUERY" ]]; then
    echo "ERROR: --folder-id and --query are required" >&2
    usage >&2
    exit 1
fi

# --- duration parser: 30m | 2h | 1d -> seconds ---
parse_duration() {
    local d="$1"
    local n="${d%[a-zA-Z]*}"
    local u="${d#$n}"
    case "$u" in
        s) echo "$n" ;;
        m) echo $((n * 60)) ;;
        h) echo $((n * 3600)) ;;
        d) echo $((n * 86400)) ;;
        *) echo "ERROR: bad window '$d', use Ns/Nm/Nh/Nd" >&2; exit 1 ;;
    esac
}

window_s=$(parse_duration "$WINDOW")

# --- timestamps (RFC3339 UTC) ---
if date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    # macOS / BSD date
    FROM=$(date -u -v-"${window_s}"S '+%Y-%m-%dT%H:%M:%SZ')
    TO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
else
    # GNU date
    FROM=$(date -u -d "@$(( $(date -u '+%s') - window_s ))" '+%Y-%m-%dT%H:%M:%SZ')
    TO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

# --- token ---
TOKEN=$(yc iam create-token 2>/dev/null) || {
    echo "ERROR: 'yc iam create-token' failed. Run 'yc init' first." >&2
    exit 2
}

# --- request body ---
BODY=$(jq -nc \
    --arg q "$QUERY" \
    --arg from "$FROM" \
    --arg to "$TO" \
    '{queries:[{value:$q,name:"v"}], fromTime:$from, toTime:$to, downsampling:{maxPoints:100}}')

# --- call ---
URL="https://monitoring.api.cloud.yandex.net/monitoring/v2/data/read?folderId=$FOLDER_ID"

response=$(curl -sS -w '\n%{http_code}' \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -X POST "$URL" -d "$BODY")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" != 2* ]]; then
    echo "ERROR: API returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 2
fi

if [[ "$RAW" -eq 1 ]]; then
    echo "$body" | jq '.'
fi

# --- analyze ---
metric_count=$(echo "$body" | jq '.metrics | length')
if [[ "$metric_count" == "0" ]]; then
    echo "FAIL: response has zero metrics. Query parsed but matched no series." >&2
    echo "Check: metric name, 'service' label, label globs (not regex), folderId." >&2
    exit 3
fi

# Count non-NaN values across all returned timeseries
nonnan=$(echo "$body" | jq '[.metrics[].timeseries.doubleValues[] | select(. != null and . == .)] | length')
total=$(echo "$body" | jq '[.metrics[].timeseries.doubleValues[]] | length')

if [[ "$nonnan" == "0" ]]; then
    echo "FAIL: $metric_count series returned, but all $total values are NaN." >&2
    echo "Likely: metric stopped being pushed, or counter is flat." >&2
    exit 4
fi

# Sample a value
sample=$(echo "$body" | jq -r '.metrics[0].timeseries.doubleValues | map(select(. != null and . == .)) | last')
labels=$(echo "$body" | jq -c '.metrics[0].labels')

cat <<EOF
OK  metrics=$metric_count  non_nan_points=$nonnan/$total  window=$WINDOW
    sample (series 0, last non-NaN): $sample
    labels (series 0): $labels
    verified_at: $TO
EOF
