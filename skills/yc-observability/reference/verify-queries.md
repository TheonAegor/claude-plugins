# Verifying SeleQL queries against the YC data API

Use this before pasting a query into an alert or dashboard. Catches empty-result and wrong-metric-name bugs that would otherwise silently break the alert.

## The data API

YC Monitoring exposes a public REST data API (unlike v3 dashboards REST, which is broken):

- `POST https://monitoring.api.cloud.yandex.net/monitoring/v2/data/read`
- Auth: `Authorization: Bearer <IAM token>`
- Body:
  ```json
  {
    "queries": [{"value": "<SeleQL query>", "name": "v"}],
    "fromTime": "<RFC3339>",
    "toTime":   "<RFC3339>",
    "downsampling": {"maxPoints": 100}
  }
  ```
- For the query to resolve, the request URL takes folder context via query string:
  `?folderId=<folder>`

## Quick check via the helper script

```bash
${CLAUDE_PLUGIN_ROOT}/skills/yc-observability/scripts/yc-query.sh \
  --folder-id b1gjc34r3qr46f364o5b \
  --query 'series_sum(non_negative_derivative("luvento_back.http_requests_total"{service="custom"}))' \
  --window 1h
```

Exits 0 with sample value on success; exits non-zero on empty/NaN/error.

## Doing it by hand

```bash
TOKEN=$(yc iam create-token)
FOLDER=b1gjc34r3qr46f364o5b
FROM=$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ')   # macOS; on linux: date -u -d '-1 hour' '+...'
TO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  "https://monitoring.api.cloud.yandex.net/monitoring/v2/data/read?folderId=$FOLDER" \
  -d "$(jq -nc --arg q 'series_sum("luvento_back.http_requests_total"{service="custom"})' \
        --arg from "$FROM" --arg to "$TO" \
        '{queries:[{value:$q,name:"v"}], fromTime:$from, toTime:$to, downsampling:{maxPoints:100}}')" \
  | jq '.'
```

## Diagnosing common failures

Response shape on success (abbreviated):
```json
{
  "metrics": [
    {
      "name": "v",
      "type": "DGAUGE",
      "labels": {...},
      "timeseries": {"timestamps": [...], "doubleValues": [...]}
    }
  ]
}
```

### Empty `metrics` array

The query parsed, but no series matched.

- **Metric name typo.** `luvento_back.http_requests_total` vs `luvento_back_http_requests_total` (the dot/underscore matters — YC namespaces with dots).
- **Wrong `service` label.** Custom metrics pushed by unified-agent carry `service="custom"`; node-exporter carries `service="node_exporter"`. Without this label, queries match nothing.
- **Label glob, not regex.** `code=~"5.."` (PromQL) doesn't work — use `code="5*"`. See [seleql-cheatsheet.md](seleql-cheatsheet.md).
- **Folder mismatch.** The metric is pushed to a different folder than you're querying. Double-check `folderId`.

### Non-200 response with `code: "INVALID_ARGUMENT"`

SeleQL syntax error. The error `message` usually points to the bad token. Most common: using PromQL functions (`rate`, `irate`, `delta`) that don't exist in SeleQL. See cheatsheet.

### Non-200 with `code: "PERMISSION_DENIED"`

The IAM token's subject lacks `monitoring.viewer` on the folder. If you ran `yc iam create-token` as yourself, your user has access; if you used an SA, grant `monitoring.viewer` to that SA.

### Response has metrics but all values are NaN

The query produced a result but no data points in the window. Either:

- The window is too short and the underlying counter hasn't seen activity (`non_negative_derivative` on a flat counter is 0 not NaN, so NaN usually means *no underlying samples at all*).
- The metric stopped being pushed (unified-agent down? service crashed?).

Widen the window to 24h and try again. If still NaN, the metric isn't actually being collected.

## What "verified" means

A query is verified when the data API returns a non-empty `metrics` array AND at least one non-NaN value across the requested window. The `scripts/yc-query.sh` helper enforces both.

For alerts, also verify the query under expected conditions: e.g., for "5xx rate > 5%", run the query during a known-healthy hour to confirm it returns a small positive number (not a huge one — which would mean labels are wrong and the alert would page constantly).
