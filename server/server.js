const express = require('express');
const dotenv = require('dotenv');
const cors = require('cors');
const connectDB = require('./config/db');
const multer = require('multer');
const path = require('path');
// Multer storage config for product images
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, path.join(__dirname, 'uploads'));
  },
  filename: function (req, file, cb) {
    const ext = path.extname(file.originalname);
    cb(null, `${Date.now()}-${Math.round(Math.random() * 1e9)}${ext}`);
  }
});
const upload = multer({ storage });



dotenv.config();
connectDB();


const app = express();
// Serve uploads as static files (must be after app is initialized)
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

app.use(cors({
  origin: [
    'http://localhost:5173',
    'https://sagana-mu.vercel.app'
  ],
  credentials: true
}));
app.use(express.json());

// Routes
app.use('/api/v1/auth', require('./routes/authRoutes'));
app.use('/api/v1/products', require('./routes/productRoutes'));
app.use('/api/v1/inventory', require('./routes/inventoryRoutes'));
app.use('/api/v1/orders', require('./routes/orderRoutes'));

// Health check
app.get('/', (req, res) => {
  res.json({ message: 'SAGANA API is running!' });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ success: false, message: 'Internal Server Error' });
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));