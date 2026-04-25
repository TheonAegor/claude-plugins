# Testing

luvvano Go services standardize on:

- **`github.com/stretchr/testify`** — `assert`, `require`, `mock` (rarely; we prefer mockery-generated mocks)
- **`github.com/vektra/mockery`** — interface mocks generated from `Service` / `Storage` / client interfaces
- **`*_test.go`** files placed next to the code they test
- **`internal/tests/`** for cross-package integration tests, gated on `TEST_DATABASE_URL`
- **`api-tests/`** with **godog** for end-to-end BDD scenarios (luvento-back only)

## Mockery setup

Each service owns a `.mockery.yml` (or `.mockery.yaml`) that lists the interfaces to mock and where to place them. Generated files are committed to the repo.

```yaml
# .mockery.yml
with-expecter: true
packages:
  github.com/luvvano/luvento-back/internal/service/property:
    interfaces:
      Storage:
        config:
          dir: internal/service/property/mocks
```

Regenerate with `mockery` from the repo root:

```bash
mockery
```

If you change an interface, regenerate the mock — do not hand-edit generated files.

## Unit test for a service

## ✅ Right: table-driven, mockery mocks for storage

```go
// internal/service/property/service/property_test.go
func TestPropertyService_Create(t *testing.T) {
    type deps struct {
        storage   *propertyMocks.MockStorage
        txManager *databaseMocks.MockTransactionManager
    }
    type args struct {
        ctx context.Context
        p   *models.Property
    }

    tests := []struct {
        name    string
        setup   func(d deps)
        args    args
        wantErr bool
    }{
        {
            name: "happy path",
            setup: func(d deps) {
                d.txManager.EXPECT().Transaction(mock.Anything, mock.Anything).
                    Run(func(ctx context.Context, fn database.Handler, _ ...database.TransactionOpt) {
                        _ = fn(ctx)
                    }).
                    Return(nil)
                d.storage.EXPECT().Create(mock.Anything, mock.Anything).
                    Return(&models.Property{UUID: testUUID}, nil)
                d.storage.EXPECT().CreateUserProperty(mock.Anything, mock.Anything, mock.Anything, mock.Anything).
                    Return(nil)
            },
            args: args{ctx: ctxWithUser(t), p: &models.Property{Name: "X"}},
        },
        {
            name: "storage error bubbles",
            setup: func(d deps) {
                d.txManager.EXPECT().Transaction(mock.Anything, mock.Anything).
                    Run(func(ctx context.Context, fn database.Handler, _ ...database.TransactionOpt) {
                        _ = fn(ctx)
                    }).
                    Return(errors.New("db down"))
            },
            args:    args{ctx: ctxWithUser(t), p: &models.Property{Name: "X"}},
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            d := deps{
                storage:   propertyMocks.NewMockStorage(t),
                txManager: databaseMocks.NewMockTransactionManager(t),
            }
            tt.setup(d)
            svc := service.New(zap.NewNop(), d.storage, d.txManager, &config.Config{})
            err := svc.Create(tt.args.ctx, tt.args.p)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
        })
    }
}
```

Things this gets right:
- Fresh mocks per `t.Run` (mocks tied to `*testing.T` auto-fail if unfulfilled).
- `zap.NewNop()` so tests don't print logs.
- The `txManager` mock actually executes the inner function — a no-op `Return(nil)` would silently skip the body and pass.

## ❌ Wrong: testing the service through a real DB

```go
func TestPropertyService_Create(t *testing.T) {
    db := openTestDB(t)
    svc := service.New(zap.NewNop(), storage.New(db, ...), realTxManager(db), nil)
    _ = svc.Create(ctx, &models.Property{Name: "X"})
}
```

That's an integration test for the storage. The service test should mock storage so the failure points at the service's logic, not at SQL.

## Storage integration test

For storage code, use a real PostgreSQL gated on `TEST_DATABASE_URL`:

## ✅ Right

```go
// internal/tests/notification_storage_integration_test.go
func notificationTestDB(t *testing.T) *sqlx.DB {
    dsn := os.Getenv("TEST_DATABASE_URL")
    if dsn == "" {
        t.Skip("TEST_DATABASE_URL not set")
    }
    db, err := sqlx.Connect("postgres", dsn)
    require.NoError(t, err)
    t.Cleanup(func() { _ = db.Close() })
    return db
}

func TestStorage_Create_Idempotent(t *testing.T) {
    db := notificationTestDB(t)
    s := storage.New(db, zap.NewNop())

    eventID := uuid.NewString()
    id1, err := s.Create(context.Background(), eventID, 1, []byte("{}"))
    require.NoError(t, err)
    id2, err := s.Create(context.Background(), eventID, 1, []byte("{}"))
    require.NoError(t, err)
    require.Equal(t, id1, id2, "ON CONFLICT DO NOTHING should keep the original id")
}
```

The test skips silently when the DB env var is missing so CI without a DB still passes.

## Naming

```text
TestComponent_Method                          // simple
TestComponent_Method_WhenCondition            // behavior
TestComponent_Method_WhenCondition_ReturnsX   // very explicit
```

Use whichever flavor the surrounding tests in that package use. Consistency matters more than the exact form.

## What to test

Focus on:
- Branches in service methods (happy path, business-rule rejection, dependency failure).
- Storage queries with non-trivial logic (filters, upserts, paging) via integration tests.
- Error mapping in handlers (sentinel → gRPC status).

Skip:
- Pure proto ↔ domain mapping helpers (auto-generated tests are noise).
- Trivial single-line getters.
- Logging side effects.

## Coverage

Aim for ~70-80% on service packages, lower on handlers (mostly mapping), and treat storage integration tests as a binary "covered or not" — if a query is non-trivial, it deserves a test.

Run only what you wrote:

```bash
go test ./internal/service/property/...
go test -race ./internal/service/property/service
```

Always run with `-race` in CI to catch goroutine bugs in syncers / workers.

## What about godog (BDD)?

`api-tests/` in `luvento-back` uses godog. Add scenarios there only when you genuinely need a black-box happy-path test against the running service. Most regressions are easier to catch with unit + storage integration tests.

## Test data

- UUIDs: use `uuid.NewString()` per test, never reuse a hardcoded one.
- Timestamps: pass a `clock` interface or freeze with a small helper; avoid `time.Now()` directly in code under test.
- Fixtures: keep them inline. A 200-line `testdata/` JSON for a 20-line test is more obscure than helpful.
