# YC Monitoring Dashboards

Full automation works. Source of truth is JSON in git, deployed by CI via the `yandexcloud` Python gRPC SDK.

## Reference implementation in luvano/infra

If the project follows the luvano/infra layout, dashboards live at:

```
dashboard/yandex_monitoring/<name>.json
.github/workflows/deploy-yc-dashboard.yml
.github/workflows/scripts/deploy_yc_dashboards.py
```

Read `dashboard/yandex_monitoring/README.md` in that repo before making changes — it documents the exact upsert semantics (List → match by name → Update with etag, else Create) and the workflow's behavior on edits made through the YC UI (local file is source of truth, UI edits get overwritten on next push).

## File ↔ dashboard mapping

- One file = one dashboard.
- Filename basename (without `.json`) becomes the YC dashboard `name`.
- `name` regex: `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$` — lowercase, digits, hyphens. **No underscores.**
- Do NOT put `folderId` or `name` inside the JSON; the deploy script injects them.

Renaming a file = creating a new dashboard in YC. The old one is **not** deleted automatically. Delete it in the YC UI or extend the script with a prune step.

## Why gRPC SDK, not REST or yc CLI

Documented in luvano/infra's dashboard README:

- **REST v3** for dashboards returns Solomon-style empty 404 even with a valid IAM token. Don't try to use curl against `/monitoring/v3/dashboards/...`.
- **`yc` CLI** has no `monitoring dashboard` command in current builds.
- **`yandexcloud` SDK** ships protobuf stubs generated from cloudapi protos; the gRPC service is reachable. This is the supported path.

Auth: SA authorized-key JSON → `yandexcloud.SDK(service_account_key=...)` mints and refreshes IAM tokens.

## Schema gotchas

The JSON is parsed with `google.protobuf.json_format.ParseDict(body, msg, ignore_unknown_fields=False)`. Every field must match the proto exactly, in **camelCase**.

Common mismatches (these will cause `ParseError`):

| Wrong | Right | Note |
|---|---|---|
| `chart.name` | `chart.title` | `ChartWidget` has no `name` field |
| `visualization_settings` | `visualizationSettings` | camelCase only |
| `visualizationSettings.type: "line"` | `visualizationSettings.type: "VISUALIZATION_TYPE_LINE"` | enum **name**, not lowercased value |
| `target.text_mode` | `target.textMode` | bool; set `true` to use raw query strings |
| `position: {top, left}` | `position: {x, y, w, h}` | integers, 12-column grid |

When in doubt, read the proto:

- [`dashboard.proto`](https://github.com/yandex-cloud/cloudapi/blob/master/yandex/cloud/monitoring/v3/dashboard.proto)
- [`widget.proto`](https://github.com/yandex-cloud/cloudapi/blob/master/yandex/cloud/monitoring/v3/widget.proto)
- [`chart_widget.proto`](https://github.com/yandex-cloud/cloudapi/blob/master/yandex/cloud/monitoring/v3/chart_widget.proto)

## Validating JSON locally before commit

You can parse a dashboard JSON against the protobuf schema *without* talking to YC. Catches typos and unknown fields in seconds.

```bash
python3 -m venv /tmp/yc-venv && /tmp/yc-venv/bin/pip install --quiet 'yandexcloud>=0.300.0'
/tmp/yc-venv/bin/python - <<'PY'
import json, sys
from google.protobuf.json_format import ParseDict
from yandex.cloud.monitoring.v3.dashboard_service_pb2 import CreateDashboardRequest

with open(sys.argv[1]) as f:
    body = json.load(f)
body.setdefault("name", "validate-only")
body.setdefault("folderId", "validate-only")
req = CreateDashboardRequest()
ParseDict(body, req, ignore_unknown_fields=False)
print(f"OK: {sys.argv[1]} parses cleanly into CreateDashboardRequest")
PY
```

If you get `ParseError: Message type yandex.cloud.monitoring.v3.X has no field named foo` — the JSON has a typo or PromQL term. Fix and re-run.

## Adding a new dashboard

1. Copy an existing dashboard JSON in the same folder: `cp existing.json my-dashboard.json`. Filename = future YC dashboard name.
2. Edit `title`, `description`, `widgets`. Do NOT add `name` or `folderId` at the top level.
3. Validate locally (snippet above).
4. Verify each unique SeleQL query — see [verify-queries.md](verify-queries.md).
5. Commit + push to `main`. CI deploys via `.github/workflows/deploy-yc-dashboard.yml`.
6. Open the dashboard in YC UI. Smoke-check that all widgets show data, not "No data".

## Editing an existing dashboard

The same flow, but be aware: if someone edited the dashboard in YC UI since the last deploy, your push **will overwrite** their changes. The deploy script re-fetches `etag` each run, so it never fails on a stale etag — UI edits silently disappear.

To preserve UI edits, pull them down first:

```bash
# Quick way: open the dashboard in YC UI, "..." menu → "Edit YAML" or export → diff with local
```

There is currently no "yc-monitoring pull" tooling in this skill. If you find yourself doing this often, extend `deploy_yc_dashboards.py` with a `pull` mode that calls `GetDashboard` and writes JSON.

## When a deploy fails

Failure modes I've seen:

1. **`ParseError` from `ParseDict`** — schema mismatch. The error names the field and message type. Fix the JSON.
2. **Operation `error.code` non-zero with "invalid query"** — SeleQL syntax issue. Reproduce via the data API ([verify-queries.md](verify-queries.md)) to get the precise message, fix, redeploy.
3. **`Permission denied`** — SA missing `monitoring.editor` role on the folder. Fix in YC IAM.
4. **`Resource not found` on update** — extremely unlikely (we always List first), but means the dashboard was deleted in UI between List and Update. Re-run the deploy.
