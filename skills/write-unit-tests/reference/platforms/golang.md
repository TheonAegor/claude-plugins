# Go Testing Patterns

## Commands

```bash
# Run all tests
go test ./...

# Run package tests
go test ./internal/services/...

# Run specific test
go test -run TestEntityService_WhenValidRequest ./internal/services/...

# With race detector
go test -race ./...

# With coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Verbose
go test -v ./...
```

## Framework

Use `testify` for assertions and mocks:
- `github.com/stretchr/testify/assert` for assertions
- `github.com/stretchr/testify/require` for fatal assertions
- `github.com/stretchr/testify/mock` for mocks
- `github.com/stretchr/testify/suite` for test suites

## Table-Driven Tests

```go
func TestEntityService_Process(t *testing.T) {
    tests := []struct {
        name        string
        entityID    string
        isValid     bool
        repoErr     error
        wantErr     bool
        wantSuccess bool
    }{
        {name: "valid entity", entityID: "e1", isValid: true, wantSuccess: true},
        {name: "invalid entity", entityID: "e2", isValid: false, wantSuccess: false},
        {name: "repo error", entityID: "e3", repoErr: errors.New("db"), wantErr: true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            mockRepo := new(mocks.EntityRepository)
            mockRepo.On("IsValid", mock.Anything, tt.entityID).Return(tt.isValid, tt.repoErr)
            svc := service.New(mockRepo)

            result, err := svc.Process(context.Background(), tt.entityID)

            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.Equal(t, tt.wantSuccess, result.Success)
        })
    }
}
```

## Mock Generation

Use `mockery` to generate mocks from interfaces:

```bash
mockery --name=EntityRepository --output=mocks --outpkg=mocks
```

Mocks are typically placed in a `mocks/` directory within the package.

## Naming Convention

```text
TestComponentName_MethodName (for simple tests)
TestComponentName_WhenCondition_ThenResult (for behavior tests)
```

## Test File Naming

Place test files next to the code being tested: `entity_service_test.go` alongside `entity_service.go`.

## Coverage Target

- Minimum: 70%
- Service layer: 80-90%
- Always run with `-race` flag in CI
