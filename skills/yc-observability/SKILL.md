---
name: yc-observability
description: Use when creating, editing, or verifying Yandex Cloud Monitoring dashboards and alerts, or when validating that a SeleQL query returns real data before pasting it into the YC console. Triggers on terms "YC Monitoring", "Yandex dashboard", "Yandex alert", "SeleQL", "monitoring.api.cloud.yandex.net".
---

# Yandex Cloud Monitoring (yc-observability)

Working with Yandex Cloud Monitoring — dashboards, alerts, and metric/query verification. Compensates for the fact that YC Monitoring tooling is unevenly available across surfaces (CLI, SDK, Terraform, REST), which causes agents to confidently use commands that don't exist.

## Hard constraints (verified 2026-05-12 — re-verify if these surfaces change)

| Surface | Dashboards | Alerts |
|---|---|---|
| `yc` CLI | **No** monitoring commands at all | **No** monitoring commands at all |
| Public gRPC SDK (`yandexcloud` Python) | Works (`yandex.cloud.monitoring.v3.dashboard_service_pb2`) | **No alert protos exist** in cloudapi repo |
| REST API v3 | Returns Solomon-style 404 even with valid IAM token | No public endpoint |
| Terraform provider | `yandex_monitoring_dashboard` | **No** `yandex_monitoring_alert` (open issue [#166](https://github.com/yandex-cloud/terraform-provider-yandex/issues/166) since 2021) |
| Web UI | Yes | **Yes — and it is the only path** |
| REST data API v2 (`/monitoring/v2/data/{read,write}`) | — | Used only for query verification, not CRUD |

### What this means in practice

- **Do NOT propose `yc monitoring …` commands.** They do not exist.
- **Do NOT propose `yandex_monitoring_alert` Terraform.** It does not exist.
- **Do NOT try to extend a Python gRPC script to create alerts.** No proto stubs are published.
- **Alert CRUD must go through the YC Web UI manually.** The skill turns this into a structured, reviewable workflow via YAML configs in the repo.

## When to use which sub-workflow

```
              ┌─ dashboards     → reference/dashboards.md
Task type  ───┼─ alerts         → reference/alerts.md
              ├─ verify a query → reference/verify-queries.md
              └─ SeleQL syntax  → reference/seleql-cheatsheet.md
```

## Sub-workflows

Load the reference file relevant to the task. Each reference is self-contained.

- [Dashboards (full automation via gRPC SDK)](${CLAUDE_PLUGIN_ROOT}/skills/yc-observability/reference/dashboards.md) — JSON → commit → CI deploys. Schema gotchas, query gotchas, debugging `ParseError`.
- [Alerts (semi-manual YAML + UI workflow)](${CLAUDE_PLUGIN_ROOT}/skills/yc-observability/reference/alerts.md) — describe in YAML, verify query, copy to UI by checklist, version in git.
- [Verifying SeleQL queries](${CLAUDE_PLUGIN_ROOT}/skills/yc-observability/reference/verify-queries.md) — REST `/data/read` with `yc iam create-token`, asserts on non-empty / non-NaN response.
- [SeleQL ≠ PromQL cheatsheet](${CLAUDE_PLUGIN_ROOT}/skills/yc-observability/reference/seleql-cheatsheet.md) — the gotchas that trip everyone migrating from Prom.

## Reusable tooling

- `scripts/yc-query.sh` — auths via `yc iam create-token` and POSTs a SeleQL query to the data API. Prints the raw response and exits non-zero on empty/error. See [verify-queries.md](${CLAUDE_PLUGIN_ROOT}/skills/yc-observability/reference/verify-queries.md) for usage.
- `templates/alert.yaml` — canonical alert config schema for repo storage.
- `templates/dashboard.json` — minimal dashboard skeleton with one chart widget.

## Common mistakes (load reference for fixes)

| Symptom | Cause | Fix |
|---|---|---|
| "yc monitoring alert ..." prints `unknown command` | yc CLI has no monitoring group | See `reference/alerts.md` — no CLI path exists |
| Dashboard deploy fails with `ParseError: no field ...` | JSON field is camelCase mismatch or PromQL term | See `reference/dashboards.md` schema gotchas |
| Query in alert returns empty | Wrong metric name, label glob is regex-style, or `service` label missing | See `reference/verify-queries.md` |
| `non_negative_derivative(...[5m])` rejected | SeleQL has no time-window arg on rate functions | See `reference/seleql-cheatsheet.md` |

## Re-verifying constraints

The "no alert API" finding is the single biggest constraint of this skill. If a future Yandex Cloud release changes this, the alerts workflow can become fully automated. Re-check by running:

```bash
# Does cloudapi expose alert protos now?
gh api repos/yandex-cloud/cloudapi/contents/yandex/cloud/monitoring/v3 \
  --jq '.[].name | select(contains("alert"))'

# Does the Terraform provider expose alert resources now?
gh api repos/yandex-cloud/terraform-provider-yandex/contents/yandex \
  --jq '.[].name | select(contains("alert"))'

# Does yc CLI gain a monitoring group?
yc monitoring --help 2>&1 | head -3
```

If any of these return non-empty / non-error, update this skill.
