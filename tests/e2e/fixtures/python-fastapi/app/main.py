from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="E2E Test API")


class HealthResponse(BaseModel):
    status: str


class Item(BaseModel):
    name: str
    price: float
    description: str | None = None


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    return HealthResponse(status="healthy")


@app.get("/items/{item_id}")
async def get_item(item_id: int):
    """Get item by ID."""
    # Placeholder - would connect to DB
    return {"item_id": item_id, "name": "Sample Item"}


@app.post("/items")
async def create_item(item: Item):
    """Create a new item."""
    # Placeholder - would save to DB
    return {"id": 1, **item.model_dump()}
