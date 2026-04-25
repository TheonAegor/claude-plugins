# Handler Layer

## File placement: segment by transport

Handlers live under `internal/handler/<transport>/<domain>.go`. A property domain that exposes both gRPC and REST gets two files:

```
internal/handler/
├── grpc/property.go
├── rest/property.go
└── queue/property.go        # if a Kafka/queue consumer exists
```

`luvento-back` still has a flat `internal/handler/<domain>.go` layout from earlier days. Treat that as **legacy** — new handlers go in the segmented dirs. `notification-service` is the reference for the right shape (see `internal/handler/grpc/` and `internal/handler/rest/` there).

## ❌ Wrong: extending the legacy flat layout

```
internal/handler/property.go        # gRPC server methods next to REST helpers in one file
```

A reviewer who does not know the file's history cannot tell which transport each method serves.

## ✅ Right: segmented

```
internal/handler/grpc/property.go   # only gRPC methods on PropertyHandler (gRPC variant)
internal/handler/rest/property.go   # only REST handlers, distinct struct
```

Handlers are the gRPC-facing boundary. They:

1. Accept the proto request.
2. Validate input (cheap checks: required fields, parseable UUIDs, enum ranges).
3. Translate proto types into domain types.
4. Call the service.
5. Translate domain results / errors into proto responses or `status.Status`.

They do **not** contain business rules, do not run queries, do not orchestrate multiple services — that is the service layer's job.

## Handler struct

## ✅ Right: explicit dependencies, embedded `Unimplemented*Server`

```go
type PropertyHandler struct {
    pb.UnimplementedPropertyServiceServer
    propertyService property.Service
    bookingService  booking.Service
    l               *zap.Logger
}

func NewPropertyHandler(
    propertyService property.Service,
    bookingService booking.Service,
    l *zap.Logger,
) *PropertyHandler {
    return &PropertyHandler{
        propertyService: propertyService,
        bookingService:  bookingService,
        l:               l,
    }
}
```

Embedding `pb.UnimplementedPropertyServiceServer` lets the proto evolve (new methods) without breaking compilation.

## ❌ Wrong: handler holds storage directly

```go
type PropertyHandler struct {
    pb.UnimplementedPropertyServiceServer
    db *sqlx.DB           // skips the service layer
    s3 *s3.Client         // skips the service layer
}
```

Handlers must talk to services, not to storage or external clients.

## Method shape

## ✅ Right

```go
func (h *PropertyHandler) CreateProperty(
    ctx context.Context,
    req *pb.CreatePropertyRequest,
) (*pb.Property, error) {
    if req.GetName() == "" {
        return nil, status.Error(codes.InvalidArgument, "name is required")
    }

    p := &models.Property{
        UUID: pkgUuid.NewV4(),
        Name: req.GetName(),
        // ... map proto → domain
    }

    if err := h.propertyService.Create(ctx, p); err != nil {
        h.l.Error("create property failed",
            zap.String("name", req.GetName()),
            zap.Error(err))
        return nil, status.Errorf(codes.Internal, "create property: %v", err)
    }
    return propertyToProto(p), nil
}
```

Notes:
- Validation comes first.
- Business errors → `status.Error(codes.InvalidArgument | NotFound | PermissionDenied | ...)`.
- Internal errors → log with structured fields, then `status.Errorf(codes.Internal, ...)`.
- Mapping helpers (`propertyToProto`) live in the handler package.

## ❌ Wrong: leaking internal errors as raw errors

```go
func (h *PropertyHandler) CreateProperty(ctx context.Context, req *pb.CreatePropertyRequest) (*pb.Property, error) {
    if err := h.propertyService.Create(ctx, mapToDomain(req)); err != nil {
        return nil, err   // ← raw service error reaches the gRPC client
    }
    return mapToProto(req), nil
}
```

The gRPC framework will wrap raw errors as `codes.Unknown`, which destroys the chance for clients to react sensibly. Always go through `status.Error` / `status.Errorf` at the handler boundary.

## ❌ Wrong: doing the work in the handler

```go
func (h *PropertyHandler) CreateProperty(ctx context.Context, req *pb.CreatePropertyRequest) (*pb.Property, error) {
    // ... validation ...
    tx, _ := h.db.BeginTxx(ctx, nil)
    defer tx.Rollback()
    _, err := tx.ExecContext(ctx, "INSERT INTO properties ...")
    // ...
    tx.Commit()
}
```

The handler is performing storage work directly. Move the SQL into `<domain>/storage/` and the orchestration into `<domain>/service/`.

## Validation

Cheap, request-shape validation belongs in handlers. Business-rule validation (e.g. "user owns this property") belongs in services.

## ✅ Right: shape vs rule split

```go
// Handler: shape
if req.GetPropertyId() == "" {
    return nil, status.Error(codes.InvalidArgument, "property_id is required")
}
propertyUUID, err := uuid.Parse(req.GetPropertyId())
if err != nil {
    return nil, status.Error(codes.InvalidArgument, "property_id is not a valid uuid")
}

// Service: rule
if !s.userOwnsProperty(ctx, userUUID, propertyUUID) {
    return ErrAccessDenied
}
```

## Auth context

Every authenticated handler reads the user from `ctx` via the middleware-provided helper, not from the request:

```go
userUUIDStr, ok := middleware.GetUserID(ctx)
if !ok {
    return nil, status.Error(codes.Unauthenticated, "missing user context")
}
```

## ❌ Wrong: trusting client-supplied user_id

```go
// Anyone can pretend to be anyone.
userUUID, _ := uuid.Parse(req.GetUserId())
return h.propertyService.GetForUser(ctx, userUUID)
```

The user identity comes from the JWT / service token via middleware, never from the request body.
