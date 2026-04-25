# Go-Specific Review Patterns

## Concurrency

Check for goroutine leaks, missing synchronization, and race conditions.

**Correct** (proper goroutine lifecycle):
```go
g, ctx := errgroup.WithContext(ctx)
g.Go(func() error { return doWork(ctx) })
if err := g.Wait(); err != nil { return err }
```

**Incorrect** (fire-and-forget goroutine):
```go
go doWork(ctx) // no way to track completion or errors
```

## Error Handling

Errors must be wrapped with context using `fmt.Errorf("...: %w", err)`.

**Correct**:
```go
if err := repo.Save(ctx, entity); err != nil {
    return fmt.Errorf("save entity %s: %w", entity.ID, err)
}
```

**Incorrect**:
```go
if err := repo.Save(ctx, entity); err != nil {
    return err // no context for debugging
}
```

## Interface Design

Prefer small, focused interfaces (1-3 methods). Accept interfaces, return concrete types.

## Context Propagation

Every function that does I/O or calls external services must accept `context.Context` as first parameter.

## Resource Cleanup

Use `defer` for cleanup. Ensure `Close()`, `Stop()`, `Cancel()` calls are present for all acquired resources.

## Race Detection

Run tests with `-race` flag. Flag any shared mutable state accessed from multiple goroutines without synchronization.
