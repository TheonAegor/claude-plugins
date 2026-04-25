# Storage Layer

Storage is the only place that talks to the database. Across luvvano Go services this means **`sqlx`** for execution and **`goqu` v9** for query building. There is no GORM in current services (older docs may say otherwise — trust the code).

A storage:
- depends on a `*sqlx.DB` (or `*sqlx.Tx` for transactional methods)
- implements the `Storage` interface declared in `<domain>/domain.go`
- exposes typed methods, not generic `Query(sql string)` escape hatches
- builds SQL with `goqu`, not by `fmt.Sprintf`-ing into strings

## Storage struct

## ✅ Right

```go
const (
    PropertyTable     = "properties"
    UserPropertyTable = "user_properties"
)

type PropertyRepo struct {
    db *sqlx.DB
    l  *zap.Logger
}

func New(db *sqlx.DB, l *zap.Logger) *PropertyRepo {
    return &PropertyRepo{db: db, l: l}
}
```

Table names live as package constants, not magic strings inside queries.

## Queries with goqu

## ✅ Right: goqu builder + ToSQL + ExecContext

```go
func (r *PropertyRepo) Create(ctx context.Context, p *models.Property) (*models.Property, error) {
    q := goqu.Insert(PropertyTable).Rows(goqu.Record{
        "uuid":    p.UUID,
        "name":    p.Name,
        "country": p.Country,
        "city":    p.City,
    }).Returning("uuid", "created_date")

    sql, args, err := q.ToSQL()
    if err != nil {
        return nil, fmt.Errorf("build insert: %w", err)
    }
    if err := r.db.QueryRowxContext(ctx, sql, args...).StructScan(p); err != nil {
        return nil, fmt.Errorf("exec insert: %w", err)
    }
    return p, nil
}
```

## ❌ Wrong: hand-built SQL with fmt.Sprintf

```go
func (r *PropertyRepo) Create(ctx context.Context, p *models.Property) error {
    q := fmt.Sprintf(
        "INSERT INTO properties (uuid, name) VALUES ('%s', '%s')",
        p.UUID, p.Name,        // ← SQL injection risk
    )
    _, err := r.db.ExecContext(ctx, q)
    return err
}
```

Two problems: SQL injection, and you lose `goqu`'s consistency with the rest of the codebase.

## ❌ Wrong: raw `?` placeholders

```go
_, err := r.db.ExecContext(ctx,
    "INSERT INTO properties (uuid, name) VALUES (?, ?)",
    p.UUID, p.Name,
)
```

PostgreSQL uses `$1`, `$2`. `goqu`'s PostgreSQL dialect emits the right placeholder shape automatically — let it.

## Upserts: ON CONFLICT

## ✅ Right

```go
q := goqu.Insert(BookingSyncTable).Rows(goqu.Record{
    "user_uuid":         data.UserUUID,
    "property_uuid":     data.PropertyUUID,
    "ics_calendar_link": data.ICSCalendarLink,
}).OnConflict(goqu.DoUpdate(
    "property_uuid, ics_calendar_link",
    goqu.Record{"user_uuid": data.UserUUID},
)).Returning("id")
```

## Transactional methods

A storage method that participates in a larger transaction takes the `*sqlx.Tx` explicitly so the caller (service) can compose it.

## ✅ Right

```go
func (s *PreferenceRepo) GetForUpdate(
    ctx context.Context,
    tx *sqlx.Tx,
    userUUID string,
) (json.RawMessage, error) {
    q := goqu.From(PreferenceTable).
        Where(goqu.C("user_uuid").Eq(userUUID)).
        ForUpdate(goqu.NoWait)
    sql, args, _ := q.ToSQL()
    var raw json.RawMessage
    if err := tx.QueryRowxContext(ctx, sql, args...).Scan(&raw); err != nil {
        return nil, fmt.Errorf("select preference for update: %w", err)
    }
    return raw, nil
}
```

## ❌ Wrong: storage opens its own transaction the service does not see

If a service is already inside `txManager.Transaction(...)`, the storage method must not call `s.db.BeginTxx` again — that opens an unrelated transaction and silently breaks atomicity.

## Field tags

Models use `db:"col"` tags for sqlx scanning, plus `json:"col"` if they cross HTTP. Both are present together.

```go
type Property struct {
    UUID    uuid.UUID `db:"uuid"      json:"uuid"`
    Name    string    `db:"name"      json:"name"`
    Country int8      `db:"country"   json:"country"`
}
```

## Migrations: goose

Every schema change ships as a goose migration in `migrations/<timestamp>_<name>.sql`:

```sql
-- +goose Up
ALTER TABLE properties ADD COLUMN price NUMERIC(10,2);

-- +goose Down
ALTER TABLE properties DROP COLUMN price;
```

The Down block is mandatory and must actually reverse the change. `DROP TABLE IF EXISTS` is acceptable; `-- nothing to undo` is not.

## ❌ Wrong: changing schema without a migration

Hand-editing the database in dev will pass locally and break in CI/staging where migrations are the source of truth.

## What does NOT belong in storage

- Authorization checks (service's job).
- Validation of business rules (service's job).
- Logging successful operations at `Info` level — the service has the context to know what was achieved. Storage logs only unexpected errors at `Warn`/`Error` if at all.
- Mapping to proto / HTTP types.

A clean storage method reads almost like a SQL fragment with a Go signature wrapped around it.
