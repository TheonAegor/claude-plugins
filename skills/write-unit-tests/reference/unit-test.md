# Unit Testing Strategy

This document provides guidance for writing unit tests. Adapt patterns to the project's language and framework.

## Before You Start

Determine the project's testing setup by examining:
- Build/test commands (Makefile, package.json scripts, build.gradle tasks)
- Testing framework (from dependencies: testify, jest, junit, pytest, etc.)
- Existing test files (naming conventions, patterns, helpers)
- Coverage configuration (if any)

## Test Naming Convention

Follow the project's existing naming convention. If none exists, use When-Then format:

```text
ComponentName_WhenCondition_ThenExpectedResult
```

Examples:
- EntityService_WhenValidRequest_ThenReturnsSuccess
- EntityService_WhenInvalidInput_ThenReturnsError
- UserRepository_GetUser_ReturnsUserFromCache

## Architecture-Based Testing Strategy

### Handler/Controller Layer (70-80% coverage)

- Request validation
- Response formatting
- Error handling and status codes
- Context propagation

### Service/Business Logic Layer (80-90% coverage)

- Business rules and validation
- Service orchestration
- Error handling scenarios
- State management

### Repository/Data Access Layer (70-80% coverage)

- CRUD operations
- Query logic
- Error handling
- Connection management

### Client Layer (70-80% coverage)

- Request formatting
- Response parsing
- Error handling and retries
- Timeouts

## Parameterized / Table-Driven Tests

Use parameterized tests for multiple scenarios:

```text
// Pseudocode
testCases = [
  { name: "valid input", input: validData, expectedOutput: success, expectError: false },
  { name: "invalid input", input: badData, expectedOutput: nil, expectError: true },
  { name: "edge case", input: edgeData, expectedOutput: edgeResult, expectError: false }
]

for each testCase in testCases:
  mock = createMock(Dependency)
  mock.when("Method").thenReturn(testCase.mockReturn)
  sut = new SystemUnderTest(mock)
  result = sut.Execute(testCase.input)
  assert(result, testCase.expectedOutput)
```

## Testing with Mocks

- Mock external dependencies (databases, APIs, message brokers)
- Create mocks that implement interfaces and control return values
- Verify mock expectations after test execution

## Testing Cancellation and Timeouts

Test that code properly handles request cancellation and timeouts. Create cancelled or timed-out contexts and verify appropriate error responses.

## Best Practices

- Use table-driven tests for multiple scenarios
- Test behavior, not implementation details
- Cover all error paths (success, failure, edge cases)
- Mock external dependencies
- Test context handling (cancellation, timeouts)
- Clean up resources in tests
- Use test helpers for common setup
- Keep tests focused and independent (no shared state)

## Avoid

- Testing external libraries
- Testing generated code
- Writing redundant tests
- Testing private functions directly
- Ignoring race conditions
- Skipping cleanup
- Hardcoding test values
