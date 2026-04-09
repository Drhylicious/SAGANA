# 🌿 SAGANA
### A Web-Based Integrated Agricultural Supply Chain, Inventory, and Digital Marketplace System for the Cooperatives of Boac, Marinduque

![MERN Stack](https://img.shields.io/badge/Stack-MERN-2E7D32?style=for-the-badge)
![License](https://img.shields.io/badge/License-Academic-blue?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Live-brightgreen?style=for-the-badge)
![Version](https://img.shields.io/badge/Version-2.1-orange?style=for-the-badge)

---

## 👥 Team Members

| Name | Role |
|------|------|
| Jhon Drhy M. Salangsang | Leader & Full Stack Developer |
| John Harvey Revilloza | Backend Developer |
| John Harold Revilloza | QA / Tester |
| Marc Louie M. Yañez | Frontend Developer |

**Course:** Web Systems and Technologies 2  
**School:** Marinduque State University — College of Information and Computing Sciences

---

## 🔗 Live Links

| Resource | URL |
|----------|-----|
| 🌐 Frontend Web Application | https://sagana-mu.vercel.app |
| ⚙️ Backend API | https://sagana.onrender.com |
| 📁 GitHub Repository | https://github.com/Drhylicious/SAGANA |
| 📄 API Documentation | Postman Collection (see /docs folder) |

---

## 📋 About SAGANA

SAGANA addresses the operational inefficiencies of agricultural cooperatives in Boac, Marinduque — where manual and paper-based systems for inventory tracking, supply chain management, and market transactions result in post-harvest losses, inaccurate records, and limited market access for farmers.

The system integrates:
- 🏪 **Digital Marketplace** — SM Markets-inspired layout with search, category sidebar, and cart drawer
- 📦 **Inventory Management** — batch-level harvest tracking with real-time stock status and expiry alerts
- 🔗 **Supply Chain Tracker** — end-to-end traceability from harvest to sale
- 🔐 **Role-Based Access Control** — Admin, Farmer, and Buyer roles with JWT authentication
- 🎨 **Animated UI** — Framer Motion splash screen, page transitions, and smooth interactions

---

## ✨ Recent Updates (v2.1)

| # | Change | Description |
|---|--------|-------------|
| 1 | **Product Image Display** | Product images now shown in marketplace cards and cart, with emoji fallback |
| 2 | **Stock Status Fix** | Out of Stock status accurately reflects real inventory for all users including guests |
| 3 | **Public Inventory Endpoint** | `/inventory/available` is now public — anyone can check stock status |
| 4 | **Farmer Dashboard Fix** | Farmer dashboard now shows both approved and pending products via `/products/mine` |
| 5 | **New API Endpoints** | Added `/products/mine`, `/products/all`, `/inventory/available`, and `/auth/users` |
| 6 | **New Categories** | Added Fresh Meat and Seafood as product categories |
| 7 | **Admin Dashboard Redesign** | Sidebar navigation with Home, Products, Orders, Users, and Marketplace tabs |
| 8 | **Marketplace Redesign** | SM Markets-inspired layout with sticky search, left category sidebar, and cart drawer |
| 9 | **Splash Screen** | Animated SAGANA logo splash screen on first load using Framer Motion |

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React.js (Vite) + Tailwind CSS + React Router + Framer Motion |
| Backend | Node.js + Express.js |
| Database | MongoDB Atlas + Mongoose |
| Authentication | JWT + bcryptjs |
| Testing | Jest + Supertest + Postman + Newman |
| Deployment | Vercel (frontend) + Render (backend) |

---

## 🚀 Getting Started (Local Development)

### Prerequisites
- Node.js v18+
- MongoDB Atlas account
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/Drhylicious/SAGANA.git
cd SAGANA

# Install backend dependencies
cd server
npm install

# Install frontend dependencies
cd ../client
npm install
```

### Environment Setup

Create `server/.env`:
```
PORT=5000
MONGO_URI=your_mongodb_atlas_uri
JWT_SECRET=your_jwt_secret
NODE_ENV=development
CLIENT_URL=http://localhost:5173
```

Create `client/.env`:
```
VITE_API_URL=http://localhost:5000/api/v1
```

### Running the App

```bash
# Terminal 1 — Backend (in /server folder)
npm run dev

# Terminal 2 — Frontend (in /client folder)
npm run dev
```

Frontend: http://localhost:5173  
Backend: http://localhost:5000

---

## 📁 Project Structure

```
SAGANA/
├── client/                   # React.js frontend
│   ├── src/
│   │   ├── api/              # Axios config with JWT interceptor
│   │   ├── assets/           # SAGANA logo and static assets
│   │   ├── components/       # Navbar, ProductCard, ProtectedRoute, SplashScreen, PageWrapper
│   │   ├── context/          # AuthContext (JWT state management)
│   │   └── pages/            # Login, Register, Marketplace, AdminDashboard, FarmerDashboard, BuyerDashboard
│   └── ...
└── server/                   # Node.js/Express backend
    ├── config/               # MongoDB Atlas connection
    ├── controllers/          # auth, product, inventory, order controllers
    ├── middleware/            # authMiddleware (JWT), roleMiddleware (RBAC)
    ├── models/               # User, Product, InventoryBatch, Order
    ├── routes/               # auth, product, inventory, order routes
    └── server.js             # Entry point
```

---

## 🔐 API Endpoints

### Auth
| Method | Endpoint | Access | Description |
|--------|----------|--------|-------------|
| POST | /api/v1/auth/register | Public | Register a new user |
| POST | /api/v1/auth/login | Public | Login and receive JWT |
| GET | /api/v1/auth/me | Private | Get current user profile |
| GET | /api/v1/auth/users | Admin | Get all registered users |

### Products
| Method | Endpoint | Access | Description |
|--------|----------|--------|-------------|
| GET | /api/v1/products | Public | Get all approved products |
| GET | /api/v1/products/all | Admin | Get ALL products including unapproved |
| GET | /api/v1/products/mine | Farmer | Get farmer's own products (approved + pending) |
| GET | /api/v1/products/:id | Public | Get a single product |
| POST | /api/v1/products | Farmer | Create a product listing |
| PUT | /api/v1/products/:id/approve | Admin | Approve a product |
| DELETE | /api/v1/products/:id | Admin | Delete a product |

### Inventory
| Method | Endpoint | Access | Description |
|--------|----------|--------|-------------|
| GET | /api/v1/inventory | Admin/Farmer | Get all inventory batches |
| GET | /api/v1/inventory/available | **Public** | Get available stock for stock status display |
| GET | /api/v1/inventory/:id | Admin/Farmer | Get a single batch |
| POST | /api/v1/inventory | Farmer | Log a new harvest batch |
| PUT | /api/v1/inventory/:id | Farmer/Admin | Update a batch |
| DELETE | /api/v1/inventory/:id | Admin | Delete a batch |

### Orders
| Method | Endpoint | Access | Description |
|--------|----------|--------|-------------|
| GET | /api/v1/orders | Admin/Buyer | Get orders |
| GET | /api/v1/orders/:id | Admin/Buyer | Get single order |
| POST | /api/v1/orders | Buyer | Place a new order |
| PUT | /api/v1/orders/:id/status | Admin | Update order status |

---

## 🗂️ Product Categories

| Category | Icon |
|----------|------|
| Vegetable | 🥦 |
| Fruit | 🍎 |
| Grain | 🌾 |
| Spice | 🌶️ |
| Fresh Meat | 🥩 |
| Seafood | 🐟 |
| Other | 📦 |

---

## 📄 Project Proposal

The full project proposal document is available in the `/docs` folder.

**Certifying Agency:** Municipal Agricultural Office (MAO), Boac, Marinduque  
**Contact:** Ms. Ederlinda V. Jasmin, Municipal Agriculturist

---

## 🌱 Significance

SAGANA contributes to:
- 🇵🇭 Philippine Digital Agriculture Strategy (PDAS) 2021–2025
- 🌍 United Nations SDG 2 (Zero Hunger)
- 📈 Improved farmer income through direct market access
- 📦 Reduced post-harvest losses through digital inventory tracking

---

*Marinduque State University — Web Systems and Technologies 2 — 2nd Semester, SY 2025–2026*
