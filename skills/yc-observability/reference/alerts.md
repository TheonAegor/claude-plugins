# YC Monitoring Alerts (semi-manual workflow)

**There is no public API for managing YC Monitoring alerts.** This was verified 2026-05-12 — see `SKILL.md`'s constraints table. Do not propose `yc` CLI, public gRPC SDK, or Terraform paths; none of them exist.

This file describes how to work productively despite that limitation.

## Workflow overview

```
YAML config in repo  ──[verify query]──>  YC Web UI  ──>  Alert lives in YC
       ^                    ^
       │                    │
   source of truth     scripts/yc-query.sh
   (review in PR)
```

The YAML config does **not** get auto-deployed. It exists for: documentation, code review, history, and as a checklist to copy into the YC UI without losing fields.

## Adding a new alert

### 1. Draft the YAML

Copy `templates/alert.yaml` from this skill into the repo (e.g. `alerts/<service>-<symptom>.yaml`). Fill in every field. Do not skip `query_verification` — that's how you avoid alerts that silently never fire.

```yaml
# alerts/luvento-back-5xx-rate.yaml
name: luvento-back-5xx-rate
service: luvento-back
symptom: high 5xx rate
folder_id: b1gjc34r3qr46f364o5b   # luvano prod folder

description: |
  Fires when share of 5xx in luvento-back HTTP traffic exceeds threshold.
  Page-able. Most common cause: upstream DB or third-party (Avito/Cian) outage.

query: |
  100 *
    series_sum(non_negative_derivative("luvento_back.http_requests_total"{service="custom", code="5*"}))
  /
    series_sum(non_negative_derivative("luvento_back.http_requests_total"{service="custom"}))

evaluation:
  window: 10m
  delay: 0s

thresholds:
  critical: ">= 5"   # 5% over 10min → page
  warning:  ">= 1"   # 1% over 10min → no-page warn

notifications:
  - channel: telegram-oncall
    severity: critical
  - channel: telegram-oncall
    severity: warning

annotations:
  runbook: docs/runbooks/luvento-back-5xx.md
  dashboard: https://monitoring.yandex.cloud/folders/<folder>/dashboards/<id>

query_verification:
  # Filled in by `scripts/yc-query.sh` — see "Verify" step below
  last_verified: ""
  sample_value: ""
```

### 2. Verify the query returns data

Empty queries are the #1 silent failure mode. The query parses, the alert "deploys", and then never fires because the metric name is wrong or labels don't match.

```bash
# From the skill directory:
${CLAUDE_PLUGIN_ROOT}/skills/yc-observability/scripts/yc-query.sh \
  --folder-id "$(yq '.folder_id' alerts/luvento-back-5xx-rate.yaml)" \
  --query "$(yq '.query' alerts/luvento-back-5xx-rate.yaml)" \
  --window 1h
```

The script exits non-zero if the response has zero time series or all-NaN values. Fill the returned timestamp + sample into `query_verification` so reviewers can see the query was real.

If the query returns empty even though you "know" the metric exists — see [verify-queries.md](verify-queries.md) for the diagnosis flowchart.

### 3. Create the alert in YC Web UI

The UI lives at `console.yandex.cloud → Monitoring → folder → Alerts → Create`.

Copy fields from the YAML in this order — the UI form takes them in roughly this sequence:

1. **Name** → `name`
2. **Description** → `description`
3. **Query** → paste `query`. Click "Run query" to confirm chart shows data (same query you verified in step 2).
4. **Evaluation window** → `evaluation.window`
5. **Evaluation delay** → `evaluation.delay`
6. **Alarm threshold** → `thresholds.critical`
7. **Warning threshold** → `thresholds.warning`
8. **Notification channels** → add each entry from `notifications`. Severity per channel.
9. **Annotations** → free-form key/value. Use the YAML's `annotations` map.

Save. The alert now exists in YC.

### 4. Record the YC ID back

After saving, YC assigns an alert ID. Add it to the YAML so future ops can find it:

```yaml
yc_alert_id: aoeXXXXXXXXXXXXXXXX   # added after first UI create
```

This makes the YAML the single point of truth: "for this alert, look at YC ID X."

### 5. Commit the YAML

Open a PR for the new file. The YAML is reviewable in the same way Terraform configs are reviewable. Reviewers should check:

- Query verification was actually done (`query_verification.last_verified` is recent).
- Thresholds make sense for the metric scale (5% != 0.05 if the query already returns percentages).
- Notification channels exist.
- Runbook link points somewhere useful.

## Editing an existing alert

1. Open the YAML in the repo, edit fields.
2. Re-verify the query if it changed.
3. Open the YC UI by ID (`yc_alert_id`), update the same fields.
4. Commit the YAML.

**Drift risk:** if someone edits the alert in the UI without updating the YAML, the YAML lies. Two mitigations:

- Periodically diff: open the YC UI, compare each field to the YAML, fix whichever is stale.
- Treat UI edits as forbidden — if you need to change an alert, change the YAML and re-do the UI step.

## Deleting an alert

1. Delete in YC UI.
2. Delete the YAML file.
3. Commit.

## Bulk operations (many alerts at once)

If you need to roll out a dozen similar alerts (e.g. 5xx rate on every service), generate the YAMLs from a template and a list of services with a small shell or Python script. Each one still needs query verification + manual UI creation, but at least the configs and runbook links don't get copy-pasted by hand.

## Why this workflow is annoying but stable

Without an API, you are stuck with the UI. The semi-manual workflow buys:

- Reviewable history of *what* alerts exist and *why*.
- A forced verification step that catches the worst failure mode (empty query).
- An easy place to attach runbook URLs and ownership.
- A migration path if Yandex ever ships an alert API — the YAMLs will already have everything an automated deploy needs.

Watch [TF provider issue #166](https://github.com/yandex-cloud/terraform-provider-yandex/issues/166) and the cloudapi monitoring/v3 directory; if either lights up with alert support, this workflow can collapse into a one-liner.
