const express = require('express');
const router = express.Router();
const {
  getInventory, getInventoryBatch,
  createInventoryBatch, updateInventoryBatch,
  deleteInventoryBatch, getAvailableBatches
} = require('../controllers/inventoryController');
const { protect } = require('../middleware/authMiddleware');
const { authorize } = require('../middleware/roleMiddleware');


// Allow anyone to fetch available batches for a product (public)
router.get('/available', getAvailableBatches);

router.get('/', protect, authorize('admin', 'farmer'), getInventory);
router.get('/:id', protect, authorize('admin', 'farmer'), getInventoryBatch);
router.post('/', protect, authorize('farmer'), createInventoryBatch);
router.put('/:id', protect, authorize('farmer', 'admin'), updateInventoryBatch);
router.delete('/:id', protect, authorize('admin'), deleteInventoryBatch);

module.exports = router;