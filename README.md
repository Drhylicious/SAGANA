# 🌿 SAGANA
### A Web-Based Integrated Agricultural Supply Chain, Inventory, and Digital Marketplace System for the Cooperatives of Boac, Marinduque

![MERN Stack](https://img.shields.io/badge/Stack-MERN-2E7D32?style=for-the-badge)
![License](https://img.shields.io/badge/License-Academic-blue?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Live-brightgreen?style=for-the-badge)

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
- 🏪 **Digital Marketplace** — direct farm-to-consumer product listings
- 📦 **Inventory Management** — batch-level harvest tracking with expiry alerts
- 🔗 **Supply Chain Tracker** — end-to-end traceability from harvest to sale
- 🔐 **Role-Based Access Control** — Admin, Farmer, and Buyer roles

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React.js (Vite) + Tailwind CSS + React Router |
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
# Run backend (in /server folder)
npm run dev

# Run frontend (in /client folder)
npm run dev
```

Frontend: http://localhost:5173
Backend: http://localhost:5000

---

## 📁 Project Structure

```
SAGANA/
├── client/                 # React.js frontend
│   ├── src/
│   │   ├── api/            # Axios configuration
│   │   ├── components/     # Navbar, ProductCard, ProtectedRoute
│   │   ├── context/        # AuthContext
│   │   └── pages/          # Login, Register, Marketplace, Dashboards
│   └── ...
└── server/                 # Node.js/Express backend
    ├── config/             # Database connection
    ├── controllers/        # Business logic
    ├── middleware/         # Auth & RBAC middleware
    ├── models/             # Mongoose schemas
    ├── routes/             # API routes
    └── server.js           # Entry point
```

---

## 🔐 API Endpoints

### Auth
| Method | Endpoint | Access |
|--------|----------|--------|
| POST | /api/v1/auth/register | Public |
| POST | /api/v1/auth/login | Public |
| GET | /api/v1/auth/me | Private |

### Products
| Method | Endpoint | Access |
|--------|----------|--------|
| GET | /api/v1/products | Public |
| POST | /api/v1/products | Farmer |
| PUT | /api/v1/products/:id/approve | Admin |
| DELETE | /api/v1/products/:id | Admin |

### Inventory
| Method | Endpoint | Access |
|--------|----------|--------|
| GET | /api/v1/inventory | Admin/Farmer |
| POST | /api/v1/inventory | Farmer |
| PUT | /api/v1/inventory/:id | Farmer/Admin |

### Orders
| Method | Endpoint | Access |
|--------|----------|--------|
| GET | /api/v1/orders | Admin/Buyer |
| POST | /api/v1/orders | Buyer |
| PUT | /api/v1/orders/:id/status | Admin |

---

## 📄 Project Proposal

The full Part 1 Project Proposal document is available in the `/docs` folder of this repository.

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
