const express = require('express');
const router = express.Router();
const {
  getOrders, createOrder,
  updateOrderStatus, getOrder,
  editOrder, deleteOrder
} = require('../controllers/orderController');
const { protect } = require('../middleware/authMiddleware');
const { authorize } = require('../middleware/roleMiddleware');


router.get('/', protect, authorize('admin', 'buyer'), getOrders);
router.get('/:id', protect, authorize('admin', 'buyer'), getOrder);
router.post('/', protect, authorize('buyer'), createOrder);
// Edit order (buyer only, own order)
router.put('/:id', protect, authorize('buyer'), editOrder);
// Delete order (buyer: own, admin: any)
router.delete('/:id', protect, authorize('admin', 'buyer'), deleteOrder);
router.put('/:id/status', protect, authorize('admin'), updateOrderStatus);

module.exports = router;