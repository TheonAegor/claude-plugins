---
name: luvvano-development
description: How to write Go code that fits in luvvano organization repositories (luvento-back, booking-sync, file-storage, notification-service). Make sure to use this skill whenever you are about to add, modify, or refactor Go code in any repository whose go.mod imports github.com/luvvano/common/protobuf or github.com/luvvano/lib/v1, even if the user did not explicitly mention luvvano conventions. It captures the org-wide layered architecture (handler → service → storage), error handling, logging, database, gRPC, config, and testing patterns, with concrete do/don't snippets pulled from the real codebases.
---

# Luvvano Go Service Development

Apply when working in a Go repo whose `go.mod` references `github.com/luvvano/...` (typically `github.com/luvvano/common/protobuf/...` and/or `github.com/luvvano/lib/v1/...`). Examples in scope: `luvento-back`, `booking-sync`, `file-storage`, `notification-service`.

If you are NOT in such a repo, do not apply these rules — many are luvvano-specific (e.g. proto import path, lib/v1/config loader).

## Detection

Run once at the start of a task:

```bash
grep -E "github.com/luvvano/(common/protobuf|lib/v1)" go.mod
```

If a match is returned, treat the conventions in this skill as the local norm. If not, fall back to general Go best practices.

## The Big Picture

A luvvano Go service is a **gRPC backend** (sometimes with HTTP via gRPC-Gateway or chi) organized as:

```
service-name/
├── cmd/<entrypoint>/main.go    # wiring only
├── internal/
│   ├── service/<domain>/       # one folder per business domain
│   │   ├── domain.go           # Service + Storage interfaces, request/response types
│   │   ├── service/            # Service implementation
│   │   ├── storage/            # Storage implementation (sqlx + goqu)
│   │   └── mocks/              # mockery-generated mocks
│   ├── handler/                # transport-segmented handlers
│   │   ├── grpc/<domain>.go    # gRPC server methods
│   │   ├── rest/<domain>.go    # REST/HTTP handlers
│   │   └── queue/<domain>.go   # Kafka / queue consumers
│   ├── middleware/             # gRPC interceptors, HTTP middleware
│   ├── config/                 # Config struct + Load()
│   ├── models/                 # cross-cutting domain models (avoid; prefer per-domain)
│   └── errors/                 # cross-cutting error types (rare; prefer per-package sentinels)
├── pkg/                        # reusable utilities (database, logger wrappers, uuid, ...)
├── migrations/                 # goose SQL files
├── api-tests/                  # godog BDD tests (luvento-back only)
└── config/                     # YAML files: local.yml, dev.yml, prod.yml
```

The **rule of thumb**: organize by **feature**, not by layer. There is no top-level `internal/services/`, `internal/handlers/`, `internal/repositories/`. Each domain owns its handler/service/storage triple.

Inside `internal/handler/`, segment by **transport**, not by domain alone. A property domain that exposes both gRPC and REST has files at `internal/handler/grpc/property.go` and `internal/handler/rest/property.go` — never a single flat `internal/handler/property.go`. (`luvento-back` still has the older flat layout in places; new code must use the segmented form.)

## Shared org libraries

luvvano publishes shared utilities under `github.com/luvvano/lib/v1/...`. Prefer these over per-service `pkg/...` reimplementations:

- `github.com/luvvano/lib/v1/uuid` — UUID type + helpers. Use this, **not** a service-local `pkg/uuid` and **not** `github.com/google/uuid`.
- `github.com/luvvano/lib/v1/config` — YAML loader with env override.
- `github.com/luvvano/lib/v1/logger` — zap factory (`NewZapWithLevel`, `SetLevel`).
- `github.com/luvvano/lib/v1/db` — DB connection helpers.

If you find an old import like `github.com/luvvano/luvento-back/pkg/uuid` while adding new code, either replace it with `lib/v1/uuid` in your new file or, at minimum, do not propagate it to other services.

## Mandatory Rules

These hold across all luvvano Go services:

1. **Layer separation**: business logic lives in `service/`, data access in `storage/`, request validation in `handler/`. Do not mix.
2. **Interfaces in `domain.go`**: every domain exposes `Service` and `Storage` interfaces from `<domain>/domain.go`. Concrete types implement them. Handlers depend on `Service` interfaces, services depend on `Storage` interfaces.
3. **Constructor injection**: build dependencies in `cmd/.../main.go` and pass them through constructors. No package-level globals, no `init()` functions for service wiring.
4. **`context.Context` is the first parameter** of every method that touches I/O, cancellation, or auth context.
5. **Errors are wrapped** with `fmt.Errorf("...: %w", err)`. Sentinel errors live at the package level: `var ErrFoo = errors.New("foo")`.
6. **Logging is `*zap.Logger`** (non-sugared), injected via constructor and stored as field `l`. Never use the global `zap.L()`. Never `fmt.Sprintf` into log messages.
7. **Protos come from `github.com/luvvano/common/protobuf/<service>/v1/gen/go`** — never vendor or copy generated proto code into the service.
8. **Database access uses `sqlx` + `goqu`** (query builder). No GORM in current services, despite older docs. Transactions go through the `TransactionManager` if the service has one.
9. **Config is YAML** loaded via `github.com/luvvano/lib/v1/config` with env-var override, struct tags `yaml:"Field"`.
10. **Tests use `testify` + `mockery`-generated mocks** placed next to the code they test.

Violations should be conscious and explained, not accidental.

## Step-by-step (adding a new feature)

1. **Locate the domain.** Pick or create `internal/service/<domain>/`. If creating, scaffold:
   - `domain.go` with `Service` and `Storage` interfaces and request/response types
   - `service/<domain>.go` with constructor and methods
   - `storage/<domain>.go` with constructor and goqu-based queries
   - `mocks/` directory (populate with `mockery`)
2. **Wire it up in `cmd/.../main.go`** in the existing dependency-injection block. Order: storage → service → handler.
3. **If you add a gRPC method**: extend the proto in `github.com/luvvano/common/protobuf` (separate repo / PR), regenerate, then implement the handler. Never add ad-hoc HTTP endpoints to bypass proto changes.
4. **If you add a DB table or column**: write a goose migration in `migrations/<timestamp>_<name>.sql` with `-- +goose Up` and `-- +goose Down` blocks.
5. **Write tests** alongside the code (`*_test.go`). Use mockery mocks for the storage interface in service tests, and a real DB (via `TEST_DATABASE_URL`) for storage integration tests.
6. **Run `go vet ./...` and `go test ./...`** before claiming done.

## Layer-specific guidance

For details and concrete do/don't snippets, consult the reference files:

- [Project layout & domain package](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/project-layout.md) — folder conventions, `domain.go` shape
- [Handler layer](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/handler.md) — gRPC handlers, status code mapping, validation
- [Service layer](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/service.md) — business logic, transactions, calling other services
- [Storage layer](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/storage.md) — sqlx + goqu queries, transactions, goose migrations
- [Error handling](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/errors.md) — sentinel errors, wrapping, gRPC mapping
- [Logging](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/logging.md) — zap usage, what to log at which level
- [gRPC](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/grpc.md) — proto import, server wiring, S2S auth, interceptors
- [Config](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/config.md) — YAML loading via lib/v1/config
- [Testing](${CLAUDE_PLUGIN_ROOT}/skills/luvvano-development/reference/testing.md) — testify, mockery, integration test pattern

Read the reference file for the layer you are about to touch — they are short and concrete.

## Common pitfalls observed in the codebase

These are real anti-patterns found in the existing repos. Do not propagate them.

- **Disabled validation left as commented code** (e.g. `file-storage` path regex). If a check is unsafe to enable, replace it with a working alternative — do not ship commented dead code.
- **Skipped logging in client wrappers** (e.g. `booking-sync` `CreateBookingV2`). Outbound RPC calls should log at Debug on entry and Error on failure, like every other client method in the same file.
- **Business logic leaking across layers** (TODO `move to handler layer` in `luvento-back/internal/service/property/service/property.go`). Validation belongs in handlers, business rules in services, queries in storage. If you are reviewing existing code and find a leak, prefer fixing it locally over copying the pattern.
- **Missing RBAC checks** marked with `// TODO: allow only for admin`. New endpoints must check authorization in the handler before dispatching to the service.
- **Bypassing `TransactionManager`** by calling `db.BeginTxx` directly when a `TransactionManager` is already wired. Use `s.txManager.Transaction(ctx, func(ctx) error { ... })` so context propagation and rollback are handled uniformly.
- **`fmt.Sprintf` into log messages** instead of structured fields. Use `zap.String("k", v)` so logs are queryable in Loki.
- **Returning raw errors from gRPC handlers** when the caller expects a `status.Status`. Map at the handler boundary.

## Quality Gate

Before reporting completion:

- [ ] Code compiles (`go build ./...`) and `go vet ./...` passes
- [ ] Tests for the changed code pass (`go test ./internal/service/<domain>/...`)
- [ ] No new `init()` functions, package-level mutable state, or global loggers
- [ ] Every new exported method takes `ctx context.Context` first
- [ ] Every new error path is wrapped with `fmt.Errorf("...: %w", err)` or maps to a `status.Errorf` at the handler boundary
- [ ] Every new log site uses structured `zap` fields, no `fmt.Sprintf` in messages, no secrets logged
- [ ] If a new DB column was added, a goose migration exists with both Up and Down
- [ ] If a new gRPC method was added, the proto change is in `github.com/luvvano/common/protobuf`, not duplicated locally

## Completion

When the change is integrated, output:

```text
SKILL COMPLETE: /luvvano-development
|- Service: <luvento-back | booking-sync | file-storage | notification-service>
|- Domain touched: <domain>
|- Layers changed: <handler | service | storage | migration | proto>
|- Tests: <added/updated count>
|- Status: PASS | NEEDS_ATTENTION
```
