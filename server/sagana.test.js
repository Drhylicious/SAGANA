const request = require('supertest');
const express = require('express');
const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
app.use('/api/v1/auth', require('./routes/authRoutes'));
app.use('/api/v1/products', require('./routes/productRoutes'));
app.use('/api/v1/inventory', require('./routes/inventoryRoutes'));
app.use('/api/v1/orders', require('./routes/orderRoutes'));

// ── TEST DATA ──────────────────────────────────────────────
let adminToken, farmerToken, buyerToken;
let productId, batchId, orderId;

// ── SETUP & TEARDOWN ───────────────────────────────────────
beforeAll(async () => {
  await mongoose.connect(process.env.MONGO_URI);
});

afterAll(async () => {
  // Cleanup test data
  const User = require('./models/User');
  const Product = require('./models/Product');
  const InventoryBatch = require('./models/InventoryBatch');
  const Order = require('./models/Order');
  await User.deleteMany({ email: { $in: ['testadmin@sagana.com', 'testfarmer@sagana.com', 'testbuyer@sagana.com'] } });
  if (productId) await Product.findByIdAndDelete(productId);
  if (batchId) await InventoryBatch.findByIdAndDelete(batchId);
  if (orderId) await Order.findByIdAndDelete(orderId);
  await mongoose.connection.close();
});

// ══════════════════════════════════════════════════════════
// AUTH TESTS
// ══════════════════════════════════════════════════════════
describe('Auth Routes', () => {

  test('POST /auth/register — should register an admin user', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ name: 'Test Admin', email: 'testadmin@sagana.com', password: 'password123', role: 'admin' });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.token).toBeDefined();
    expect(res.body.user.role).toBe('admin');
    adminToken = res.body.token;
  });

  test('POST /auth/register — should register a farmer user', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ name: 'Test Farmer', email: 'testfarmer@sagana.com', password: 'password123', role: 'farmer' });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.user.role).toBe('farmer');
    farmerToken = res.body.token;
  });

  test('POST /auth/register — should register a buyer user', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ name: 'Test Buyer', email: 'testbuyer@sagana.com', password: 'password123', role: 'buyer' });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.user.role).toBe('buyer');
    buyerToken = res.body.token;
  });

  test('POST /auth/register — should reject duplicate email', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ name: 'Duplicate', email: 'testadmin@sagana.com', password: 'password123', role: 'admin' });
    expect(res.statusCode).toBe(400);
    expect(res.body.success).toBe(false);
  });

  test('POST /auth/login — should login with correct credentials', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'testadmin@sagana.com', password: 'password123' });
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.token).toBeDefined();
  });

  test('POST /auth/login — should reject wrong password', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'testadmin@sagana.com', password: 'wrongpassword' });
    expect(res.statusCode).toBe(401);
    expect(res.body.success).toBe(false);
  });

  test('GET /auth/me — should return current user with valid token', async () => {
    const res = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.user.email).toBe('testadmin@sagana.com');
  });

  test('GET /auth/me — should reject request without token', async () => {
    const res = await request(app).get('/api/v1/auth/me');
    expect(res.statusCode).toBe(401);
    expect(res.body.success).toBe(false);
  });

});

// ══════════════════════════════════════════════════════════
// PRODUCT TESTS
// ══════════════════════════════════════════════════════════
describe('Product Routes', () => {

  test('POST /products — farmer should create a product', async () => {
    const res = await request(app)
      .post('/api/v1/products')
      .set('Authorization', `Bearer ${farmerToken}`)
      .send({ name: 'Test Kamote', category: 'Vegetable', description: 'Fresh kamote', pricePerUnit: 25, unit: 'kg' });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.isApproved).toBe(false);
    productId = res.body.data._id;
  });

  test('POST /products — buyer should NOT create a product', async () => {
    const res = await request(app)
      .post('/api/v1/products')
      .set('Authorization', `Bearer ${buyerToken}`)
      .send({ name: 'Unauthorized Product', category: 'Fruit', pricePerUnit: 10, unit: 'piece' });
    expect(res.statusCode).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('GET /products — public should see approved products only', async () => {
    const res = await request(app).get('/api/v1/products');
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    // New product not yet approved so should not appear
    const found = res.body.data.find(p => p._id === productId);
    expect(found).toBeUndefined();
  });

  test('PUT /products/:id/approve — admin should approve a product', async () => {
    const res = await request(app)
      .put(`/api/v1/products/${productId}/approve`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.isApproved).toBe(true);
  });

  test('PUT /products/:id/approve — farmer should NOT approve a product', async () => {
    const res = await request(app)
      .put(`/api/v1/products/${productId}/approve`)
      .set('Authorization', `Bearer ${farmerToken}`);
    expect(res.statusCode).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('GET /products — public should see product after approval', async () => {
    const res = await request(app).get('/api/v1/products');
    expect(res.statusCode).toBe(200);
    const found = res.body.data.find(p => p._id === productId);
    expect(found).toBeDefined();
    expect(found.isApproved).toBe(true);
  });

});

// ══════════════════════════════════════════════════════════
// INVENTORY TESTS
// ══════════════════════════════════════════════════════════
describe('Inventory Routes', () => {

  test('POST /inventory — farmer should log a harvest batch', async () => {
    const res = await request(app)
      .post('/api/v1/inventory')
      .set('Authorization', `Bearer ${farmerToken}`)
      .send({
        product: productId,
        quantity: 100,
        harvestDate: '2026-03-25',
        expiryDate: '2026-04-25'
      });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.batchCode).toBeDefined();
    expect(res.body.data.status).toBe('Harvested');
    batchId = res.body.data._id;
  });

  test('POST /inventory — buyer should NOT log a harvest batch', async () => {
    const res = await request(app)
      .post('/api/v1/inventory')
      .set('Authorization', `Bearer ${buyerToken}`)
      .send({ product: productId, quantity: 50, harvestDate: '2026-03-25', expiryDate: '2026-04-25' });
    expect(res.statusCode).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('GET /inventory — farmer should see their own batches', async () => {
    const res = await request(app)
      .get('/api/v1/inventory')
      .set('Authorization', `Bearer ${farmerToken}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.length).toBeGreaterThan(0);
  });

  test('GET /inventory — buyer should NOT access inventory', async () => {
    const res = await request(app)
      .get('/api/v1/inventory')
      .set('Authorization', `Bearer ${buyerToken}`);
    expect(res.statusCode).toBe(403);
    expect(res.body.success).toBe(false);
  });

});

// ══════════════════════════════════════════════════════════
// ORDER TESTS
// ══════════════════════════════════════════════════════════
describe('Order Routes', () => {

  test('POST /orders — buyer should place an order', async () => {
    const res = await request(app)
      .post('/api/v1/orders')
      .set('Authorization', `Bearer ${buyerToken}`)
      .send({ product: productId, inventoryBatch: batchId, quantityOrdered: 10 });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.status).toBe('Pending');
    expect(res.body.data.totalPrice).toBe(250);
    orderId = res.body.data._id;
  });

  test('POST /orders — farmer should NOT place an order', async () => {
    const res = await request(app)
      .post('/api/v1/orders')
      .set('Authorization', `Bearer ${farmerToken}`)
      .send({ product: productId, inventoryBatch: batchId, quantityOrdered: 5 });
    expect(res.statusCode).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('POST /orders — should reject order exceeding stock', async () => {
    const res = await request(app)
      .post('/api/v1/orders')
      .set('Authorization', `Bearer ${buyerToken}`)
      .send({ product: productId, inventoryBatch: batchId, quantityOrdered: 99999 });
    expect(res.statusCode).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.message).toBe('Insufficient stock in selected batch');
  });

  test('PUT /orders/:id/status — admin should update order status', async () => {
    const res = await request(app)
      .put(`/api/v1/orders/${orderId}/status`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ status: 'Confirmed' });
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.status).toBe('Confirmed');
  });

  test('PUT /orders/:id/status — buyer should NOT update order status', async () => {
    const res = await request(app)
      .put(`/api/v1/orders/${orderId}/status`)
      .set('Authorization', `Bearer ${buyerToken}`)
      .send({ status: 'Cancelled' });
    expect(res.statusCode).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('GET /orders — buyer should see their own orders', async () => {
    const res = await request(app)
      .get('/api/v1/orders')
      .set('Authorization', `Bearer ${buyerToken}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.length).toBeGreaterThan(0);
  });

  test('GET /orders — admin should see all orders', async () => {
    const res = await request(app)
      .get('/api/v1/orders')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

});
