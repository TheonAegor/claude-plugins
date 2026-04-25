# Project Layout & Domain Package

## Folder conventions

```
service-name/
├── cmd/<entrypoint>/main.go
├── internal/
│   ├── service/<domain>/{domain.go, service/, storage/, mocks/}
│   ├── handler/
│   │   ├── grpc/<domain>.go
│   │   ├── rest/<domain>.go
│   │   └── queue/<domain>.go
│   ├── middleware/
│   ├── config/
│   └── (optional: models/, errors/, gateways/, transport/)
├── pkg/
├── migrations/
└── config/   # YAML files
```

Two crossed axes:

- **Domains** are organized by **feature** (not by layer): each business domain owns its own `service/` + `storage/` triple under `internal/service/<domain>/`.
- **Handlers** are organized by **transport**: gRPC, REST, queue handlers each get a subdirectory under `internal/handler/`. A single domain that has both gRPC and REST surfaces ends up with two files: `internal/handler/grpc/<domain>.go` and `internal/handler/rest/<domain>.go`. Don't conflate them in one file.

## ✅ Right: feature-organized

```
internal/service/property/
├── domain.go
├── service/
│   └── property.go
├── storage/
│   └── property.go
└── mocks/
    └── MockStorage.go
```

## ❌ Wrong: layer-organized

```
internal/
├── handlers/
│   ├── property.go
│   ├── booking.go
│   └── auth.go
├── services/
│   ├── property.go
│   └── booking.go
└── repositories/
    ├── property.go
    └── booking.go
```

This forces every feature to span three sibling packages and obscures domain boundaries.

## domain.go: the contract

`<domain>/domain.go` declares the `Service` and `Storage` interfaces and any shared request/response types. Implementations live in `service/` and `storage/`.

## ✅ Right: interfaces in domain.go, types co-located

```go
// internal/service/property/domain.go
package property

type Service interface {
    Create(ctx context.Context, p *models.Property) error
    Get(ctx context.Context, id uuid.UUID) (*models.Property, error)
    List(ctx context.Context, f ListFilter) ([]models.Property, error)
}

type Storage interface {
    Create(ctx context.Context, p *models.Property) (*models.Property, error)
    Get(ctx context.Context, id uuid.UUID) (*models.Property, error)
    List(ctx context.Context, f ListFilter) ([]models.Property, error)
}

type ListFilter struct {
    UserUUID uuid.UUID
    Limit    int
    Offset   int
}
```

## ❌ Wrong: interface defined in implementation file

```go
// internal/service/property/service/property.go
package service

// PropertyService interface lives here, next to the only implementation.
type PropertyService interface {
    Create(ctx context.Context, p *models.Property) error
}

type service struct { ... }
```

Two problems: the interface is now in the same package as its only implementation (so it cannot decouple anything), and consumers need to import `<domain>/service` instead of `<domain>`.

## cmd/<entrypoint>/main.go: wiring only

`main.go` is a wiring file. It loads config, builds the dependency graph, starts servers, and waits for shutdown. It does **not** contain business logic.

## ✅ Right: clear DI block

```go
// cmd/api/main.go
propertyStorage := propertyStorage.New(db, log)
propertyService := propertyService.New(log, propertyStorage, txManager, cfg)
propertyHandler := handler.NewPropertyHandler(
    propertyService, bookingService, bookingSyncer,
    bookingSyncClient, usersService, log,
)

s := grpc.NewServer(grpc.UnaryInterceptor(metrics.UnaryServerInterceptor()))
pb.RegisterPropertyServiceServer(s, propertyHandler)
```

## ❌ Wrong: business logic in main

```go
func main() {
    db := openDB()
    http.HandleFunc("/property", func(w http.ResponseWriter, r *http.Request) {
        // parsing, validation, SQL, response — all here
    })
}
```

If you find yourself reaching for `http.HandleFunc` inside `main`, you are skipping the handler/service/storage decomposition.

## When to add a new domain vs extend an existing one

- **Same business entity, new operation** → add a method to the existing `Service`/`Storage` interfaces.
- **New business entity with its own lifecycle** → new `internal/service/<new-domain>/` folder.
- **Shared utility (uuid, transactions, logger wrapper)** → `pkg/`, not `internal/service/`.

## models/ and errors/ folders

These exist in `luvento-back` but they are not the preferred home for new code. Prefer keeping models and sentinel errors **inside the domain package** that owns them. Use the cross-cutting `internal/models/` and `internal/errors/` only when a type is genuinely shared across many domains.

## Legacy flat handlers

`luvento-back` still has a flat `internal/handler/<domain>.go` layout for older code (e.g. `internal/handler/property.go`). This is **legacy** — the org has moved to transport-segmented handlers (see `notification-service/internal/handler/grpc/` and `internal/handler/rest/`).

When adding a new handler in `luvento-back`:

- ✅ Put it at `internal/handler/grpc/<domain>.go` (or `rest/`/`queue/` as appropriate).
- ❌ Do not extend the legacy flat file just because neighboring domains live there.

When refactoring is out of scope, leaving an existing flat file alone is fine — but new files go in the segmented dirs.

## Use the shared `github.com/luvvano/lib/v1` library

luvvano publishes shared utilities at `github.com/luvvano/lib/v1/...`. New code must import from there rather than reimplementing or copying into a service-local `pkg/`:

| Need | Import |
|------|--------|
| UUID type + helpers (`Parse`, `NewV4`, `TransformIdToUuid`) | `github.com/luvvano/lib/v1/uuid` |
| YAML config loader with env override | `github.com/luvvano/lib/v1/config` |
| Zap factory (`NewZapWithLevel`, `SetLevel`) | `github.com/luvvano/lib/v1/logger` |
| DB connection helpers | `github.com/luvvano/lib/v1/db` |

## ✅ Right: shared lib import

```go
import (
    "github.com/luvvano/lib/v1/uuid"
)

func (h *PropertyHandler) GetProperty(ctx context.Context, req *pb.GetPropertyRequest) (*pb.Property, error) {
    id, err := uuid.Parse(req.GetId())
    if err != nil {
        return nil, status.Error(codes.InvalidArgument, "invalid id")
    }
    // ...
}
```

## ❌ Wrong: per-service local uuid package

```go
import (
    pkgUuid "github.com/luvvano/luvento-back/pkg/uuid"
)
```

This was the old pattern; `luvento-back` still has ~109 files importing it. New code should not extend that footprint.

## ❌ Wrong: third-party uuid directly

```go
import "github.com/google/uuid"
```

The shared `lib/v1/uuid` already wraps a third-party UUID lib (`gofrs/uuid/v5`) with an org-specific `UUID` type and helpers like `TransformIdToUuid` that you will need anyway.
