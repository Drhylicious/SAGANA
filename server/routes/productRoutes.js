const express = require('express');
const router = express.Router();
const {
  getProducts, getProduct, createProduct,
  updateProduct, approveProduct, deleteProduct, getAllProducts
} = require('../controllers/productController');
const { protect } = require('../middleware/authMiddleware');
const { authorize } = require('../middleware/roleMiddleware');

router.get('/', getProducts);
router.get('/all', protect, authorize('admin'), getAllProducts);
router.get('/:id', getProduct);
router.post('/', protect, authorize('farmer'), createProduct);
router.put('/:id', protect, authorize('farmer', 'admin'), updateProduct);
router.put('/:id/approve', protect, authorize('admin'), approveProduct);
router.delete('/:id', protect, authorize('admin'), deleteProduct);

module.exports = router;