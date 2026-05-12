# SeleQL ≠ PromQL — the gotchas

YC Monitoring uses [SeleQL](https://yandex.cloud/en/docs/monitoring/concepts/querying), not PromQL. They look superficially similar; they are not the same. The migration mistakes below burn time in every YC Monitoring repo.

## Translation table

| PromQL | SeleQL | Note |
|---|---|---|
| `rate(counter[5m])` | `non_negative_derivative(counter)` | **No time-window arg.** The chart's grid sets the window. |
| `irate(...)` | n/a | Use `non_negative_derivative`. |
| `delta(counter[5m])` | `diff(counter)` | Same — no window arg. |
| `increase(counter[1h])` | n/a directly | Approximate with `series_sum(diff(counter))` over a chart window, or use `integrate`. |
| `sum(...)` over series | `series_sum(...)` | Note: `series_sum` collapses *across series*; `sum` in PromQL is a label-aware aggregation. |
| `avg(...)` over series | `series_avg(...)` | Same caveat. |
| `histogram_quantile(0.95, ...)` | `histogram_percentile(95, "metric_bucket"{...})` | Note `histogram_percentile` takes the percentile as 0–100, not 0–1. |
| `label=~"regex"` | `label="glob"` | **No regex.** Only `*`, `?`, `\|` globs. |
| `label!~"regex"` | `label!="glob"` | Same. |
| `up == 0` | n/a directly | YC has no built-in `up` metric. Approximate via "traffic should be > 0 but is 0" alerts. |
| `absent(metric)` | `drop_nan(metric) IS NaN` (approx) | Often easier to alert on derived metric being NaN. |

### Worked example: "device not in lo/veth*/docker*"

PromQL:
```promql
node_network_receive_bytes_total{device!~"lo|veth.*|docker.*"}
```

SeleQL:
```
"node_network_receive_bytes_total"{device!="lo|veth*|docker*"}
```

Note: in SeleQL globs, `veth*` not `veth.*`. The leading `.` is a regex artifact and won't match anything.

## Conventions in this YC org

These come from how `unified-agent` is configured (`unified-agent/config.yml` in luvano/infra), not from YC itself.

- **All custom metrics carry `service="custom"`.** Unified-agent stamps this. If a query omits it, it matches nothing.
- **Metric name lives in `name` label.** `"luvento_back.http_requests_total"{...}` is sugar for `{name="luvento_back.http_requests_total", ...}`. Both forms work.
- **Per-CPU / per-disk / per-iface counters produce multiple series.** Wrap in `series_avg(...)` or `series_sum(...)` to collapse into one chart line. Without it, you get N noisy lines and aggregations behave unexpectedly.
- **Namespace prefix.** Each service's metrics get prefixed with the unified-agent namespace: `luvento_back.*`, `booking_sync.*`, `file_storage.*`, `node_exporter.*`. Don't query the unprefixed name.

## Functions worth knowing

| Function | What it does |
|---|---|
| `non_negative_derivative(c)` | Per-second rate; clamps to 0 on counter resets. The SeleQL `rate(...)`. |
| `diff(c)` | Difference between adjacent points (no per-second). |
| `series_sum(...)` / `series_avg(...)` / `series_min` / `series_max` | Collapse multiple series. |
| `drop_nan(...)` | Filter out NaN points. Useful when downstream math chokes on gaps. |
| `histogram_percentile(p, "bucket_metric"{...})` | Quantile from a Prometheus-style histogram exported under YC. p is 0–100. |
| `alias("template", ...)` | Rename series for legend. Supports `{{label}}` templates. |
| `integrate(...)` | Cumulative integral; PromQL `increase` approximation over the chart window. |
| `as_count(...)` | Treat a gauge as a count (rare; useful for special graph types). |

## Common mistakes (and what the error usually looks like)

- **Time window argument on rate function.** `non_negative_derivative(counter[5m])` → `INVALID_ARGUMENT`. Drop the `[5m]`.
- **Regex labels.** `code=~"5.."` → "no such label operator" or empty result depending on context. Use `code="5*"`.
- **PromQL-only function.** `rate(...)`, `irate(...)`, `histogram_quantile(...)` → parse error. Translate.
- **Forgot `service` label.** Query parses fine, returns empty. Verify via [verify-queries.md](verify-queries.md).
- **Mixed up percentile scale.** `histogram_percentile(0.95, ...)` returns garbage. Use `95`, not `0.95`.

## When in doubt

The fastest feedback loop is the YC UI's Metric Explorer:

1. console.yandex.cloud → Monitoring → Metric Explorer
2. Paste the query
3. Errors show inline; data plots immediately
4. Once it works, copy it to JSON / YAML

`scripts/yc-query.sh` is the headless equivalent for scripting.
