# gRPC

luvvano services expose **gRPC** as their primary API; some also serve HTTP via grpc-gateway (luvento-back) or chi (file-storage). Protos are **never** vendored locally — they are imported from the central proto repo.

## Proto import path

## ✅ Right

```go
import (
    pb            "github.com/luvvano/common/protobuf/luvento-back/v1/gen/go"
    bookingSyncPb "github.com/luvvano/common/protobuf/booking-sync/v1/gen/go"
    notifPb       "github.com/luvvano/common/protobuf/notification-service/v1/gen/go"
)
```

The pattern is `github.com/luvvano/common/protobuf/<service>/v<N>/gen/go`. There are no `.proto` files inside the service repos — only the import.

## ❌ Wrong: vendored generated code

```go
import pb "github.com/luvvano/luvento-back/internal/pb/v1"   // ← do not duplicate
```

Adding generated proto code to a service repo means proto changes drift between services. Every service depends on the same `common/protobuf` so they cannot diverge.

## When you need to add a proto method

1. Add the method to the `.proto` file in `github.com/luvvano/common/protobuf` (separate repo, separate PR).
2. Regenerate (`buf generate` or the repo's Makefile target).
3. Bump the dependency in the service's `go.mod` and update the implementation.

If you find yourself writing a new HTTP handler to skip step 1, stop and add the proto method instead.

## Server wiring in main.go

## ✅ Right

```go
// cmd/api/main.go (luvento-back, condensed)
s := grpc.NewServer(
    grpc.UnaryInterceptor(metrics.UnaryServerInterceptor()),
    // chain interceptors as needed
)
pb.RegisterPropertyServiceServer(s, propertyHandler)
pb.RegisterBookingServiceServer(s, bookingHandler)
reflection.Register(s)

go func() {
    lis, err := net.Listen("tcp", ":"+cfg.GRPC.Port)
    if err != nil {
        log.Fatal("listen", zap.Error(err))
    }
    log.Info("starting gRPC", zap.String("port", cfg.GRPC.Port))
    if err := s.Serve(lis); err != nil {
        log.Fatal("serve", zap.Error(err))
    }
}()
```

Two things to keep:
- `reflection.Register(s)` so `grpcurl` works against the service in dev/staging.
- The serve loop in a goroutine, with the main goroutine blocked on `<-ctx.Done()` for graceful shutdown.

## Graceful shutdown

## ✅ Right

```go
go func() {
    <-ctx.Done()
    log.Info("shutting down gRPC")
    s.GracefulStop()

    shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    if err := healthServer.Shutdown(shutdownCtx); err != nil {
        log.Error("shutdown health server", zap.Error(err))
    }
}()
```

`GracefulStop` lets in-flight RPCs finish. `Stop()` is for emergencies, not for normal shutdown.

## Service-to-service auth

Server-side: validate `x-service-name` + `x-service-token` (or a Bearer token) in a unary interceptor. Use **constant-time comparison** for tokens — `subtle.ConstantTimeCompare`.

## ✅ Right (server interceptor)

```go
func ServiceTokenInterceptor(cfg ServiceAuthConfig, log *zap.Logger) grpc.UnaryServerInterceptor {
    expected := []byte(cfg.Token)
    return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
        md, ok := metadata.FromIncomingContext(ctx)
        if !ok {
            return nil, status.Error(codes.Unauthenticated, "missing metadata")
        }
        tokens := md.Get("authorization")
        if len(tokens) == 0 {
            return nil, status.Error(codes.Unauthenticated, "missing authorization")
        }
        token := strings.TrimPrefix(tokens[0], "Bearer ")
        if subtle.ConstantTimeCompare([]byte(token), expected) != 1 {
            return nil, status.Error(codes.Unauthenticated, "invalid token")
        }
        return handler(ctx, req)
    }
}
```

## ✅ Right (client side adds metadata via interceptor)

```go
func (c *BookingClient) serviceAuthInterceptor(
    ctx context.Context, method string, req, reply any,
    cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption,
) error {
    md := metadata.New(map[string]string{
        "x-service-name":  c.serviceName,
        "x-service-token": c.serviceToken,
    })
    if existing, ok := metadata.FromOutgoingContext(ctx); ok {
        md = metadata.Join(existing, md)
    }
    ctx = metadata.NewOutgoingContext(ctx, md)
    return invoker(ctx, method, req, reply, cc, opts...)
}
```

## ❌ Wrong: comparing tokens with `==`

```go
if token != cfg.Token { ... }   // timing-attack-friendly
```

## ❌ Wrong: passing the service token in the request body

```proto
message ListBookingsRequest {
    string service_token = 1;   // ← do not put auth in the payload
}
```

Auth lives in the metadata, just like in HTTP it lives in headers, not in JSON.

## Interceptor chaining

When you need multiple interceptors (metrics + auth + recovery), chain them via `grpc.ChainUnaryInterceptor`:

```go
s := grpc.NewServer(
    grpc.ChainUnaryInterceptor(
        recovery.UnaryServerInterceptor(),
        metrics.UnaryServerInterceptor(),
        middleware.ServiceTokenInterceptor(cfg.ServiceAuth, log),
        middleware.JWTAuthInterceptor(jwtSecret),
    ),
)
```

## Health checks

Every service should expose a `/health` HTTP endpoint (or a gRPC health-check service) that the orchestrator can probe. Keep it cheap — no DB roundtrip on every probe; instead, set a flag from a periodic background ping.

## Status codes (when mapping at the handler boundary)

| Domain situation | gRPC code |
|------------------|-----------|
| Bad input shape (missing field, unparsable UUID) | `codes.InvalidArgument` |
| Authenticated but not allowed | `codes.PermissionDenied` |
| No auth context at all | `codes.Unauthenticated` |
| Resource does not exist | `codes.NotFound` |
| Resource already exists / version conflict | `codes.AlreadyExists` / `codes.FailedPrecondition` |
| Anything internal you cannot recover from | `codes.Internal` |
| External dependency timed out | `codes.DeadlineExceeded` (or propagate) |

`codes.Unknown` is a smell — it means the handler returned a raw `error`. Map it.
