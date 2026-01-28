# Go API Fixture

E2E test fixture representing a performance-focused Go API.

## Stack
- Go 1.21+
- Gin web framework
- PostgreSQL (mocked for testing)

## Commands
- `go run cmd/api/main.go` - Start server
- `go test ./...` - Run tests
- `go build -o api cmd/api/main.go` - Build binary

## Testing Scenarios
- Add new endpoint
- Add database integration
- Add middleware
