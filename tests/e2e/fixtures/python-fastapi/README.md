# Python FastAPI Fixture

E2E test fixture representing an AI/ML API stack.

## Stack
- FastAPI
- Pydantic v2
- SQLAlchemy
- LangChain (for AI features)
- pytest + pytest-asyncio

## Commands
- `uvicorn app.main:app --reload` - Start dev server
- `pytest` - Run tests
- `ruff check .` - Lint

## Testing Scenarios
- Add new API endpoint
- Add LangChain integration
- Add database model
