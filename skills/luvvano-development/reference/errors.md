# Error Handling

Three rules:

1. Errors are **wrapped** with `fmt.Errorf("context: %w", err)` as they cross function boundaries.
2. Sentinel errors are declared at the **package** level: `var ErrFoo = errors.New("foo")`.
3. Errors are mapped to gRPC `status.Status` only at the **handler boundary** — never inside services or storage.

## Sentinel errors

## ✅ Right: per-package sentinels named `Err<Subject>`

```go
// internal/handler/errors.go
package handler

import "errors"

var (
    ErrUserNotFound = errors.New("user not found")
    ErrAccessDenied = errors.New("access denied")
    ErrOrgNotFound  = errors.New("organization not found")
)
```

```go
// internal/service/inapp/domain.go
package inapp

import "errors"

var ErrNotFound = errors.New("notification not found")
```

Callers compare with `errors.Is(err, inapp.ErrNotFound)`.

## ❌ Wrong: stringly-typed errors

```go
if err.Error() == "not found" {
    // brittle — any wrapping breaks this
}
```

`errors.Is` and `errors.As` exist for a reason. Use them.

## Wrapping

## ✅ Right: each layer adds its short context

```go
// storage
return fmt.Errorf("build insert query: %w", err)

// service
return fmt.Errorf("create property: %w", err)

// handler
h.l.Error("create property failed", zap.Error(err))
return nil, status.Errorf(codes.Internal, "create property: %v", err)
```

The wrapped chain is human-readable and `errors.Is(err, sentinel)` still works.

## ❌ Wrong: dropping the cause

```go
if err := s.repo.Create(ctx, p); err != nil {
    return errors.New("could not create property")   // ← original err lost
}
```

You have just thrown away the cause. The next on-call engineer will hate this.

## ❌ Wrong: double-wrapping with %v

```go
return fmt.Errorf("create property: %v", err)   // ← stringifies, breaks errors.Is
```

Use `%w` to preserve the chain. Use `%v` only at the very edge (e.g. `status.Errorf` payloads sent over the wire).

## Mapping to gRPC at the handler boundary

## ✅ Right

```go
func (h *PropertyHandler) GetProperty(ctx context.Context, req *pb.GetPropertyRequest) (*pb.Property, error) {
    p, err := h.propertyService.Get(ctx, parseUUID(req.GetId()))
    switch {
    case errors.Is(err, property.ErrNotFound):
        return nil, status.Error(codes.NotFound, "property not found")
    case errors.Is(err, handler.ErrAccessDenied):
        return nil, status.Error(codes.PermissionDenied, "access denied")
    case err != nil:
        h.l.Error("get property failed", zap.String("id", req.GetId()), zap.Error(err))
        return nil, status.Errorf(codes.Internal, "get property: %v", err)
    }
    return propertyToProto(p), nil
}
```

The handler is the single place that knows about gRPC codes. Services and storage stay framework-free.

## ❌ Wrong: status codes in services

```go
// internal/service/property/service/property.go
import "google.golang.org/grpc/codes"

func (s *PropertyService) Get(...) (..., error) {
    if !found {
        return nil, status.Error(codes.NotFound, ...)   // ← service knows about gRPC
    }
}
```

Now the service cannot be called from a non-gRPC context (HTTP route, CLI, test) without re-interpreting status codes. Return a sentinel error from the service, map it in the handler.

## ❌ Wrong: returning raw errors from handlers

```go
return nil, err   // gRPC will tag this codes.Unknown
```

Always go through `status.Error` / `status.Errorf` at the handler boundary so clients get a meaningful code.

## Logging vs returning

Errors are logged **once**, where they have the most context — usually at the handler when an internal error is being mapped to `codes.Internal`. Lower layers wrap and return; only the boundary logs. This avoids the "same error logged five times in the trace" smell.

## Validation errors

For request-shape errors a single `status.Error(codes.InvalidArgument, "<field>: <reason>")` is enough. For multi-field validation (e.g. notification-service `[]FieldError`), aggregate into the message:

```go
return nil, status.Errorf(codes.InvalidArgument, "validation failed: %v", validationErrors)
```

## Don't catch panics in regular code

Recovery from panics belongs in interceptors (gRPC `recovery` interceptor, HTTP middleware). Application code should panic only on truly impossible states (programmer errors), and even then prefer `log.Fatal` at startup.
