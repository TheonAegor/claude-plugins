# Logging

All luvvano Go services use **`go.uber.org/zap`**, **non-sugared**. The logger is constructed at startup (typically via `github.com/luvvano/lib/v1/logger`'s `NewZapWithLevel`) and **injected by constructor** as a field, conventionally named `l` (or `log` in `main.go` and clients).

## Construction

## ✅ Right: build once in main, inject everywhere

```go
// cmd/api/main.go
log, lvl, err := libLogger.NewZapWithLevel(libLogger.WithLevel(libLogger.LevelDebug))
if err != nil {
    panic(err)
}
defer log.Sync()
libLogger.SetLevel(lvl, cfg.LogLevel)

propertyService := propertyService.New(log, propertyStorage, txManager, cfg)
```

```go
// internal/service/property/service/property.go
type PropertyService struct {
    l *zap.Logger
    // ...
}
```

## ❌ Wrong: package-level global

```go
var log = zap.NewExample()   // ← cannot be configured per environment, cannot be muted in tests

func (s *PropertyService) Create(...) { log.Info(...) }
```

## ❌ Wrong: re-init logger inside a constructor

```go
func New(...) *PropertyService {
    l, _ := zap.NewProduction()     // ignores cfg.LogLevel, leaks goroutine on shutdown
    return &PropertyService{l: l}
}
```

## Structured fields, never Sprintf

## ✅ Right

```go
s.l.Info("property updated",
    zap.String("property_uuid", id.String()),
    zap.String("user_uuid", userID.String()),
    zap.Int("version", version),
)
```

## ❌ Wrong

```go
s.l.Info(fmt.Sprintf("property %s updated by %s", id, userID))
```

Sprintf'd messages are not queryable in Loki — you cannot `{job="luvento-back"} | property_uuid="..."` against them.

## Levels

| Level | When |
|-------|------|
| `Debug` | Per-call traces, RPC entry/exit, payload sizes. Off in production by default. |
| `Info`  | Successful business events that change state: "property created", "booking confirmed", "calendar event synced", "smtp connected". |
| `Warn`  | Recovered conditions: retry succeeded, fallback used, partial cleanup failure. The system is still healthy. |
| `Error` | Operation failed and could not be recovered locally. Always include `zap.Error(err)`. |
| `Fatal` | Only at startup, when continuing would mean serving wrong results (DB unreachable, required config missing). Avoid elsewhere — `Fatal` calls `os.Exit(1)`, skipping defers. |

## ✅ Right

```go
s.l.Debug("creating calendar event",
    zap.Int64("booking_sync_id", id),
    zap.String("ics_event_id", evt.UID))

s.l.Info("calendar event created",
    zap.Int64("event_id", eventID),
    zap.String("ics_event_id", evt.UID))

s.l.Warn("could not delete image variant; continuing",
    zap.String("key", key),
    zap.Error(err))

s.l.Error("send notification failed",
    zap.String("event_id", req.EventID),
    zap.Error(err))
```

## What NOT to log

- **Secrets**: passwords, JWTs, service tokens, SMTP credentials, S3 secret keys.
- **Whole user objects** when only the UUID is needed — they tend to contain PII.
- **Successful endpoint calls at Info on every request** — that's metrics' job, not logs.
- **Trivial control flow** ("entering function X", "got 0 errors") — noise.
- **`err` after you have already returned an HTTP/gRPC error from it** — log once, at the boundary that has the full context.

## ❌ Wrong: logging a credential

```go
log.Info("smtp connecting",
    zap.String("user", cfg.SMTP.Username),
    zap.String("password", cfg.SMTP.Password),   // ← never
)
```

## ❌ Wrong: re-logging the same error at each layer

```go
// storage
r.l.Error("query failed", zap.Error(err))
return err
// service
s.l.Error("create failed", zap.Error(err))
return err
// handler
h.l.Error("create failed", zap.Error(err))
return nil, status.Errorf(codes.Internal, ...)
```

The handler has the full request context (user_id, request_id) and wraps the chain — that is where the single log line belongs. Lower layers wrap and return.

## Client wrappers: log entry at Debug, error at Error

When you wrap a generated gRPC client, follow the existing pattern in the codebase:

```go
func (c *BookingClient) ListBookings(ctx context.Context, req *pb.ListBookingsRequest) (*pb.ListBookingsResponse, error) {
    c.logger.Debug("listing bookings")
    resp, err := c.client.ListBookings(ctx, req)
    if err != nil {
        c.logger.Error("list bookings failed", zap.Error(err))
        return nil, fmt.Errorf("list bookings: %w", err)
    }
    c.logger.Info("bookings listed", zap.Int("count", len(resp.Bookings)))
    return resp, nil
}
```

If you find a method in an existing client wrapper that **does not** log on error, that's a bug in that file — fix it, do not propagate the omission.

## Sugared logger

The codebase uses the strongly-typed (`*zap.Logger`) API everywhere, not the sugared one (`*zap.SugaredLogger`). Stick with it for consistency, even though `Infow("msg", "k", v)` is shorter — `zap.String("k", v)` is what reviewers will expect.
