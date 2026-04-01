const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, path.join(__dirname, '../uploads'));
  },
  filename: function (req, file, cb) {
    const ext = path.extname(file.originalname);
    cb(null, `${Date.now()}-${Math.round(Math.random() * 1e9)}${ext}`);
  }
});
const upload = multer({ storage });
const {
  getProducts, getProduct, createProduct,
  updateProduct, approveProduct, deleteProduct, getAllProducts, getPriceDropProducts, getMyProducts
} = require('../controllers/productController');
const { protect } = require('../middleware/authMiddleware');
const { authorize } = require('../middleware/roleMiddleware');

router.get('/', getProducts);
router.get('/mine', protect, authorize('farmer'), getMyProducts);
router.get('/price-drops', getPriceDropProducts);
router.get('/all', protect, authorize('admin'), getAllProducts);
router.get('/:id', getProduct);
router.post('/', protect, authorize('farmer'), upload.single('image'), createProduct);
router.put('/:id', protect, authorize('farmer', 'admin'), upload.single('image'), updateProduct);
router.put('/:id/approve', protect, authorize('admin'), approveProduct);
router.delete('/:id', protect, authorize('farmer', 'admin'), deleteProduct);

module.exports = router;