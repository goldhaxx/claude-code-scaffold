# Test Observability — BTS-497

Local-only OpenTelemetry stack for ccanvil's bats test suite. Spans flow from each `@test` through an OTel Collector into Grafana Tempo; a deterministic flattener also produces a `jq`-readable per-test JSONL sidecar at `.ccanvil/state/test-runs.jsonl` for offline / agent-driven queries.

Schema is runner-neutral (per `SCHEMA.md`) so the same pipeline extends to pytest / vitest / go-test under BTS-499.

## Quickstart

```bash
# One-time: install otel-cli (the bats helper invokes it per test).
brew install equinix-labs/otel-cli/otel-cli

# One-time: pre-create the bind-mount target as a FILE. If absent, Docker
# auto-creates it as a DIRECTORY, which makes the Collector's fileexporter
# fail silently and confuses the failure mode at suite-end with exit 78.
touch .ccanvil/observability/raw-traces.jsonl

# Start the stack (Collector + Tempo + Grafana, all on 127.0.0.1).
docker compose -f .ccanvil/observability/docker-compose.yml up -d

# Run the bats suite — every test now emits a span.
bash .ccanvil/scripts/bats-report.sh --parallel

# Open the dashboard:
open http://127.0.0.1:3001            # Grafana (admin/admin)
#   → Dashboards → ccanvil → ccanvil — Test observability
```

## Reading the dashboard

One dashboard — `ccanvil — Test observability` — answers the four questions you
actually have, in four stacked sections:

| Section | Answers | Panels |
|---|---|---|
| **NOW** | What is the suite doing right now? | Recent suite roots; Live test feed (last 200 tests, 5s auto-refresh) |
| **SLOW** | What dragged the suite? | Slowest tests (24h); Slowest files (24h) |
| **DIDN'T PASS** | What should I look at first? | Failed tests (24h); Failures count (24h) |
| **TREND** | How are things moving over time? | Suite history (7d) — pass/fail/total per run |

**To see the full waterfall of a run:** in the *Recent suite roots* (or *Suite
history*) panel, click the **Span ID** link. Grafana opens the Tempo trace view
showing the nested `suite → file → test` hierarchy with per-span timing bars.

### Tempo query modes (Explore → Tempo)

When you go to **Explore** and pick the Tempo datasource, the query-type toggle
offers three modes — they answer different questions:

| Mode | Use it to | Note |
|---|---|---|
| **Search** | Browse recent traces with a point-and-click filter builder. | Easiest for "show me recent runs." |
| **TraceQL** | Run an explicit query like `{ resource.service.name="ccanvil-test" && status = error }`. | What the dashboard panels use. **`=~` is full-line implicit-anchored** — write `name =~ "bats suite.*"`, NOT `name =~ "^bats suite"` (the `^` makes it never match). |
| **TraceID** | Jump straight to one trace's waterfall by its 32-hex ID. | This is what the Span ID links do. |

A single TraceQL search returns at most 100 spans per spanset (`spss` param);
the dashboard panels set `spss` explicitly where they need more than the
default 3.

## Start / Stop / Status

```bash
# Bring up the stack.
docker compose -f .ccanvil/observability/docker-compose.yml up -d

# Stop the stack but keep volumes (traces/dashboards survive).
docker compose -f .ccanvil/observability/docker-compose.yml stop

# Tear down + delete volumes (clean slate).
docker compose -f .ccanvil/observability/docker-compose.yml down -v

# Check container status.
docker compose -f .ccanvil/observability/docker-compose.yml ps
```

## Healthcheck

| Service | Endpoint | Expected |
|---|---|---|
| Collector | `http://127.0.0.1:13133` | `{"status":"Server available", ...}` |
| Tempo | `http://127.0.0.1:3200/ready` | `ready` (200) |
| Grafana | `http://127.0.0.1:3001/api/health` | `{database:ok, ...}` |

One-liner:

```bash
for url in http://127.0.0.1:13133 http://127.0.0.1:3200/ready http://127.0.0.1:3001/api/health; do
  echo "$url: $(curl -fsS -o /dev/null -w '%{http_code}' "$url")"
done
```

Tempo's `/ready` returns 503 for ~25s after first start (ingester warm-up) — re-check after a wait.

## Port allocation

| Port | Service | Purpose |
|---|---|---|
| 3001 | Grafana | Dashboards (host); container default :3000 remapped to avoid colliding with any other Grafana the operator is running. |
| 3200 | Tempo | HTTP API + Grafana datasource. |
| 4317 | Collector | OTLP gRPC receiver. |
| 4318 | Collector | OTLP HTTP receiver (the bats helper uses this). |
| 13133 | Collector | `health_check` extension. |

All ports bind to `127.0.0.1` only — the stack is local-only by design. No external access.

## Opt out (substrate self-tests, offline)

The bats suite runs without the OTel stack when `--no-telemetry` is passed:

```bash
bash .ccanvil/scripts/bats-report.sh --parallel --no-telemetry
```

Effects:
- Disables the bats helper's per-test span emission (no curl, no otel-cli).
- Skips the post-run flatten step (a missing `raw-traces.jsonl` does not propagate exit 78).
- `docs-check.sh test-suite-run` skips its AC-2 healthcheck precondition.

Useful when iterating on substrate that itself touches the helper, when running offline, or when the stack is intentionally down.

## Troubleshooting

**Suite-run aborts with `ERROR: OTel Collector healthcheck unreachable`.** The dispatcher's AC-2 precondition fires before bats forks. Start the stack (`docker compose up -d`) or pass `--no-telemetry` to bypass.

**`otel-cli not on PATH` during suite-run.** The bats helper's setup_file requires `otel-cli`. Install: `brew install equinix-labs/otel-cli/otel-cli`.

**Exit code 78 from bats-report.sh.** Per AC-12d, exit 78 (sysexits.h `EX_CONFIG`) means the post-run `otel-flatten.sh` failed — almost always either (a) the Collector is down so no spans were emitted, or (b) `raw-traces.jsonl` is missing/malformed. Check the stderr line above the exit; usually points at the recovery action.

**Some tests don't appear in Tempo / test-runs.jsonl.** Common causes: commas in test names (the helper sanitizes them to semicolons; if you see commas back, the sanitization broke); test never wired the helper into its setup_file (only the 10-file Phase D sample is instrumented as of BTS-497 — full rollout in BTS-504).

**Healthcheck returns 200 but no spans land in `raw-traces.jsonl`.** Almost certainly the bind-mount footgun: Docker auto-created `raw-traces.jsonl` as a DIRECTORY when the host path was absent at `docker compose up` time. Diagnose with `file .ccanvil/observability/raw-traces.jsonl` — if it says "directory" rather than "empty"/"ASCII text," that's the bug. Fix: `docker compose down`, `rm -rf .ccanvil/observability/raw-traces.jsonl`, `touch .ccanvil/observability/raw-traces.jsonl`, `docker compose up -d`.

**Tempo says `/ready` returns 503.** Normal for ~25s after fresh start. Wait. If persistent, check `docker compose logs tempo` for ingester errors.

**Grafana dashboard panels show "no data".** Confirm spans are landing via `curl -fsS 'http://127.0.0.1:3200/api/search?q=%7B%20resource.service.name%3D%22ccanvil-test%22%20%7D' | jq`. If spans are in Tempo but panels are empty, check the panel's TraceQL query for an `^`-anchored regex — Tempo's `=~` is full-line implicit-anchored, so `name =~ "^bats suite"` never matches; use `name =~ "bats suite.*"`.

**A panel shows fewer spans than expected.** Tempo caps spans-per-spanset; the panel target needs an explicit `spss` value (max 100). The dashboard's live-feed and slowest-tests panels set this.

**A panel's rows reshuffle on every refresh even though no tests ran.** This is the TraceQL `limit` truncation footgun. Tempo applies `limit` *during* a streaming block-merge, not after a global sort — so when the number of matching traces exceeds `limit`, each search returns a different arbitrary subset. The dashboard panels set `limit` to 500 (well above realistic single-user volume) so the full set always returns — no truncation, stable set — and add `sortBy` transformations (with `Span ID` as a deterministic secondary key, so equal-duration rows can't swap) so the display order is pinned too. If you ever run more than ~500 suite runs inside a panel's time window, raise the panel `limit` further; otherwise the reshuffle returns.

**Why the panels have no "Trace Name" / "Trace Service" column.** Tempo computes a trace's root span name (`rootTraceName`) at query time. For a trace whose spans are all rootless — e.g. a run emitted before the BTS-504 hierarchy linking, or a long run fragmented across many storage blocks — there is no single root, so Tempo picks an arbitrary span and the value flickers between refreshes. The dashboard hides both columns: the per-row identity comes from the span's own `Name` / `test.file` / attributes, and the `Span ID` link is the drill-in handle to the full waterfall. The dashboard never depends on `rootTraceName`.

## Files in this directory

| File | Purpose |
|---|---|
| `docker-compose.yml` | Three-service stack: Collector + Tempo + Grafana. |
| `otel-collector-config.yaml` | OTLP receivers + Tempo exporter + fileexporter + healthcheck. |
| `tempo.yaml` | Tempo single-binary config (local backend, 7d retention). |
| `grafana/provisioning/datasources/tempo.yaml` | Auto-registered Tempo datasource. |
| `grafana/provisioning/dashboards/test-runs.yaml` | Dashboard provider config. |
| `grafana/provisioning/dashboards/ccanvil-test-observability.json` | The dashboard — NOW / SLOW / DIDN'T PASS / TREND sections. |
| `otel-flatten.sh` | Deterministic OTLP → flat JSONL normalizer (AC-10, AC-12). |
| `otel-span.sh` | Generic OTel span helper library — sourceable; any script can emit spans (BTS-543). |
| `SCHEMA.md` | Span schema + flat record schema contract (v1.0.0). |
| `.gitignore` | Excludes the live `raw-traces.jsonl` from git. |
| `raw-traces.jsonl` | Local-only Collector output (gitignored). |

## Reference

- Spec: `docs/specs/bts-497-test-otel-stack.md` (Linear: BTS-497).
- Research: `docs/research/test-performance-research.md` (4-stream open-market scan that converged on this architecture).
- Follow-up tickets: BTS-498 (drift-guard outlier), BTS-499 (Stage-2 distillation), BTS-500 (metrics layer), BTS-501 (logs layer), BTS-502 (regression alerts), BTS-504 (remaining bats wiring).
