const request = require('supertest');
const { app, seedData } = require('../app');

beforeEach(() => {
    seedData();
});

describe('Legacy App', () => {
    test('GET /api/health returns ok', async () => {
        const res = await request(app).get('/api/health');
        expect(res.statusCode).toBe(200);
        expect(res.body.status).toBe('ok');
    });

    test('GET /api/items returns paginated items', async () => {
        const res = await request(app).get('/api/items');
        expect(res.statusCode).toBe(200);
        expect(res.body.items).toBeDefined();
        expect(res.body.total).toBe(3);
    });

    test('POST /api/register creates user', async () => {
        const res = await request(app)
            .post('/api/register')
            .send({
                email: 'test@example.com',
                password: 'password123',
                name: 'Test User'
            });
        expect(res.statusCode).toBe(200);
        expect(res.body.email).toBe('test@example.com');
    });

    test('POST /api/register fails without email', async () => {
        const res = await request(app)
            .post('/api/register')
            .send({ password: 'password123' });
        expect(res.statusCode).toBe(400);
    });
});
