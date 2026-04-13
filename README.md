# 🌿 SAGANA
### A Web-Based Integrated Agricultural Supply Chain, Inventory, and Digital Marketplace System for the Payanas Cooperative of Torrijos, Marinduque

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

SAGANA addresses the operational inefficiencies of the Payanas Cooperative of Torrijos, Marinduque — where manual and paper-based systems for inventory tracking, supply chain management, and market transactions result in post-harvest losses, inaccurate records, and limited market access for farmers.

The system integrates:
- 🏪 **Digital Marketplace** — SM Markets-inspired layout with search, category sidebar, and cart drawer
- 📦 **Inventory Management** — batch-level harvest tracking with real-time stock status and expiry alerts
- 🔗 **Supply Chain Tracker** — end-to-end traceability from harvest to sale
- 🔐 **Role-Based Access Control** — Admin, Farmer, and Buyer roles with JWT authentication
- 📊 **Predictive Analytics** — Real MongoDB data-driven planting calendar with yield score charts
- 🎨 **Animated UI** — Framer Motion splash screen, page transitions, and smooth interactions

---

## ✨ Recent Updates (v2.1)

| # | Change | Description |
|---|--------|-------------|
| 1 | **Product Image Display** | Product images shown in marketplace cards and cart, with emoji fallback |
| 2 | **Stock Status Fix** | Out of Stock status reflects real inventory for all users including guests |
| 3 | **Public Inventory Endpoint** | `/inventory/available` is public — anyone can check stock status |
| 4 | **Farmer Dashboard Fix** | Shows both approved and pending products via `/products/mine` |
| 5 | **Buyer Order Management** | Buyers can now edit quantity and delete their own orders |
| 6 | **Predictive Analytics** | Real MongoDB data powers the Marinduque Smart Planting Calendar |
| 7 | **Dual Analytics Charts** | Predictive Yield Score (0–100 smoothed) vs Actual Harvest History (raw data) |
| 8 | **New Categories** | Added Fresh Meat and Seafood as product categories |
| 9 | **Admin Dashboard Redesign** | Sidebar navigation with Home, Products, Orders, Users tabs |
| 10 | **Marketplace Redesign** | SM Markets-inspired layout with sticky search, left category sidebar, and cart |
| 11 | **Splash Screen** | Animated SAGANA logo splash screen on first load using Framer Motion |
| 12 | **Branding Update** | Updated to Payanas Cooperative of Torrijos, Marinduque (SP3) |

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React.js (Vite) + Tailwind CSS + React Router + Framer Motion + Recharts |
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
│   │   ├── components/       # Navbar, ProductCard, ProtectedRoute, SplashScreen, PageWrapper, AnalyticsLineChart
│   │   ├── context/          # AuthContext (JWT state management)
│   │   └── pages/            # Login, Register, Marketplace, AdminDashboard, FarmerDashboard, BuyerDashboard
│   └── ...
└── server/                   # Node.js/Express backend
    ├── config/               # MongoDB Atlas connection
    ├── controllers/          # auth, product, inventory (+ analytics), order controllers
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
| GET | /api/v1/inventory/analytics | Farmer | Get predictive analytics — returns `monthlyYields` and `predictiveScores` |
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
| PUT | /api/v1/orders/:id | Buyer | Edit own order quantity |
| PUT | /api/v1/orders/:id/status | Admin | Update order status |
| DELETE | /api/v1/orders/:id | Buyer | Delete own order (auto-syncs with Admin Dashboard) |

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

## 📊 Predictive Analytics

The Farmer Dashboard includes a **Marinduque Smart Planting Calendar** powered by real inventory data:

- **Actual Harvest History** — real `quantity` per month from `InventoryBatch` collection
- **Predictive Yield Score (0–100)** — smoothed projection with Marinduque seasonal climate adjustments
- **Optimal Planting & Harvest Windows** — calculated from actual harvest patterns
- **Predicted Growth Duration** — derived from harvest and expiry date records

---

## 📄 Project Proposal

The full project proposal document is available in the `/docs` folder.

**Certifying Organization:** Samahan ng Pagkakaisa sa Pag-unlad ng Payanas (SP3) Agriculture Cooperative  
**Location:** Torrijos, Marinduque

---

## 🌱 Significance

SAGANA contributes to:
- 🇵🇭 Philippine Digital Agriculture Strategy (PDAS) 2021–2025
- 🌍 United Nations SDG 2 (Zero Hunger)
- 📈 Improved farmer income through direct market access
- 📦 Reduced post-harvest losses through digital inventory tracking
- 🌾 Empowering the Payanas Cooperative of Torrijos, Marinduque

---

*Marinduque State University — Web Systems and Technologies 2 — 2nd Semester, SY 2025–2026*
