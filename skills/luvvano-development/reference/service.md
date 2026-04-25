# Service Layer

Services own business logic: validation rules, orchestration of multiple storages or external clients, transaction boundaries, and authorization decisions.

A service:
- depends on `Storage` interfaces (and other services' interfaces) — never on `*sqlx.DB` directly
- accepts a `*zap.Logger` and a `TransactionManager` (when transactions are needed)
- exposes methods that match its `Service` interface in `domain.go`

## Service struct

## ✅ Right

```go
type PropertyService struct {
    l         *zap.Logger
    repo      property.Storage
    txManager database.TransactionManager
    cfg       *config.Config
}

func New(
    l *zap.Logger,
    repo property.Storage,
    txManager database.TransactionManager,
    cfg *config.Config,
) *PropertyService {
    return &PropertyService{l: l, repo: repo, txManager: txManager, cfg: cfg}
}
```

## ❌ Wrong: service reaches into the DB pool

```go
type PropertyService struct {
    db *sqlx.DB   // service should not know we use sqlx
}
```

Knowing about `*sqlx.DB` couples the service to the persistence choice and breaks unit testing with mocks.

## Transactions

Use `TransactionManager.Transaction` so context propagation and rollback are uniform. The service body looks like a regular function — the manager hides `BeginTx` / `Commit` / `Rollback`.

## ✅ Right

```go
func (s *PropertyService) Create(ctx context.Context, p *models.Property) error {
    userUUIDStr, ok := middleware.GetUserID(ctx)
    if !ok {
        return fmt.Errorf("create property: missing user context")
    }
    userUUID, err := uuid.Parse(userUUIDStr)
    if err != nil {
        return fmt.Errorf("create property: parse user uuid: %w", err)
    }

    return s.txManager.Transaction(ctx, func(ctx context.Context) error {
        created, err := s.repo.Create(ctx, p)
        if err != nil {
            return fmt.Errorf("repo create: %w", err)
        }
        if err := s.repo.CreateUserProperty(ctx, created.UUID, userUUID, RelationManager); err != nil {
            return fmt.Errorf("repo create user_property: %w", err)
        }
        return nil
    })
}
```

## ❌ Wrong: ad-hoc transactions inside the service

```go
func (s *PropertyService) Create(ctx context.Context, p *models.Property) error {
    tx, _ := s.db.BeginTxx(ctx, nil)
    defer tx.Rollback()
    // ... raw SQL ...
    return tx.Commit()
}
```

Bypasses the manager, leaks `*sqlx.Tx`, and likely defeats testing.

## Calling other services

Service-to-service calls inside the same process: depend on the **interface** of the other service, not on its concrete type.

## ✅ Right

```go
type Service struct {
    repo            property.Storage
    bookingService  booking.Service     // interface
    l               *zap.Logger
}
```

## ❌ Wrong: depending on a concrete service struct

```go
type Service struct {
    bookingService *booking.BookingService   // concrete; cannot mock
}
```

## Calling other services across the network (gRPC clients)

When the dependency lives in another service (e.g. `booking-sync` calling `notification-service`), wrap the generated gRPC client in a thin local interface so the service code stays decoupled from the proto.

## ✅ Right

```go
// internal/client/notification.go
type NotificationClient interface {
    Send(ctx context.Context, req *pb.SendNotificationRequest) error
}

type notificationClient struct {
    cli pb.NotificationServiceClient
    log *zap.Logger
}

func (c *notificationClient) Send(ctx context.Context, req *pb.SendNotificationRequest) error {
    c.log.Debug("sending notification", zap.String("event_id", req.GetEventId()))
    if _, err := c.cli.SendNotification(ctx, req); err != nil {
        c.log.Error("send notification failed", zap.Error(err))
        return fmt.Errorf("send notification: %w", err)
    }
    return nil
}
```

The wrapper adds logging, lets the service mock it, and shields the rest of the code from the generated proto types.

## What logging belongs here

- Successful business events at `Info` (state changes, "property created", "booking confirmed").
- Recovered errors at `Warn` (retry succeeded, fallback used).
- Hard failures at `Error` with full context.
- Avoid logging on every method entry/exit — leave that to interceptors / metrics.

## What does NOT belong in services

- Parsing proto request fields (handler's job).
- Building SQL strings (storage's job).
- Mapping domain types to proto types (handler's job).
- HTTP / gRPC status codes (handler's job).

If you find yourself importing `google.golang.org/grpc/codes` from a `service/` file, you have crossed a layer.
