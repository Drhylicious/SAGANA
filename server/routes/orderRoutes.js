const express = require('express');
const router = express.Router();
const {
  getOrders, createOrder,
  updateOrderStatus, getOrder
} = require('../controllers/orderController');
const { protect } = require('../middleware/authMiddleware');
const { authorize } = require('../middleware/roleMiddleware');

router.get('/', protect, authorize('admin', 'buyer'), getOrders);
router.get('/:id', protect, authorize('admin', 'buyer'), getOrder);
router.post('/', protect, authorize('buyer'), createOrder);
router.put('/:id/status', protect, authorize('admin'), updateOrderStatus);

module.exports = router;