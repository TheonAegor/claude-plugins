# Go Documentation Conventions

## Package Documentation

Every non-trivial package should have a doc.go or a package comment in the main file:

```go
// Package service provides business logic for entity processing.
// It orchestrates validation, persistence, and event publishing.
package service
```

## Function Documentation

Document exported functions only when the name and signature are not self-explanatory:

```go
// ProcessEntity validates and persists the entity, then publishes the result.
// It retries transient failures up to 3 times with exponential backoff.
// On permanent failure, a dead-letter event is published instead of returning error.
func (s *Service) ProcessEntity(ctx context.Context, req *ProcessRequest) (*ProcessResult, error) {
```

## Interface Documentation

```go
// EntityRepository provides data access for entities.
// Implementations must be safe for concurrent use.
type EntityRepository interface {
    GetByID(ctx context.Context, id string) (*Entity, error)
    Save(ctx context.Context, entity *Entity) error
}
```

## Godoc Conventions

- First sentence is the summary (appears in package listings)
- Use complete sentences
- Reference parameters by name
- Document error conditions
