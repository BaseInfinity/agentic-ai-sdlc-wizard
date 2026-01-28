import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.mark.asyncio
async def test_health_check(client):
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


@pytest.mark.asyncio
async def test_get_item(client):
    response = await client.get("/items/1")
    assert response.status_code == 200
    data = response.json()
    assert data["item_id"] == 1


@pytest.mark.asyncio
async def test_create_item(client):
    item = {"name": "Test Item", "price": 9.99}
    response = await client.post("/items", json=item)
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Test Item"
