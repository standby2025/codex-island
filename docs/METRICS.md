# Prometheus usage exporter

Open Settings → General → Prometheus metrics. Enable **Usage exporter** and
set **Metrics port** (default 9464), then click **Apply**. The exporter is off
by default. Both settings persist across launches and apply immediately; disabling
it closes the listener and active connections. Changing the port restarts it.
The endpoint URL or binding error appears below the controls.

```sh
curl http://127.0.0.1:9464/metrics
```

The listener binds only to IPv4 loopback. Demo mode never starts it.
The former `CODEXISLAND_METRICS_PORT` environment variable is no longer used.

Prometheus configuration (Prometheus must run on the same host):

```yaml
scrape_configs:
  - job_name: codexisland
    scrape_interval: 60s
    static_configs:
      - targets: ['127.0.0.1:9464']
```

All metrics are gauges with `provider`, `window`, and `group` labels:

| Metric | Value |
| --- | --- |
| `codexisland_quota_available` | 1 for a valid reading without a refresh error, otherwise 0 |
| `codexisland_quota_used_ratio` | Consumed fraction, e.g. 0.3 means 30%; may exceed 1 |
| `codexisland_quota_remaining_ratio` | `max(0, 1 - used)` |
| `codexisland_quota_reset_timestamp_seconds` | Provider-reported Unix reset timestamp, when available |

Legacy windows use `fiveHour`, `weekly`, or `monthly`; other providers use their
reported metric and group IDs. Only selected providers and reported windows are
exported. Connected providers export all reported metrics, including model groups
outside the current chart selection. An unknown or failed reading omits used,
remaining, and reset samples; it never fabricates zero usage. Unlimited currency
credit amounts have no percentage measurement and report availability 0.

Scrapes read the existing app stores on the main actor and never fetch providers.
Provider refresh cadence remains 5/15/30 minutes, so a 60-second scrape can repeat
the same reading. Availability reflects the last poll status, not its age.
No account names, credential identifiers, tokens, prompts, or local session logs
are exported. Cost estimates and token history are outside this endpoint's scope.
The listener bounds request headers, concurrent connections, and connection lifetime.

Run exporter formatting fixtures with `bash scripts/test-metrics.sh`.
