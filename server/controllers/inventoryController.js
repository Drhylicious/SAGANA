const InventoryBatch = require('../models/InventoryBatch');

// @desc    Get all inventory batches
// @route   GET /api/v1/inventory
// @access  Private (Admin or Farmer)
const getInventory = async (req, res) => {
  try {
    const { status, product } = req.query;
    let query = {};

    // Farmers only see their own batches
    if (req.user.role === 'farmer') query.farmer = req.user._id;
    if (status) query.status = status;
    if (product) query.product = product;

    const batches = await InventoryBatch.find(query)
      .populate('product', 'name category unit')
      .populate('farmer', 'name email')
      .sort({ createdAt: -1 });

    res.status(200).json({ success: true, count: batches.length, data: batches });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get single inventory batch
// @route   GET /api/v1/inventory/:id
// @access  Private (Admin or Farmer owner)
const getInventoryBatch = async (req, res) => {
  try {
    const batch = await InventoryBatch.findById(req.params.id)
      .populate('product', 'name category unit')
      .populate('farmer', 'name email');

    if (!batch) {
      return res.status(404).json({ success: false, message: 'Batch not found' });
    }

    // Farmers can only view their own batches
    if (req.user.role === 'farmer' && batch.farmer._id.toString() !== req.user._id.toString()) {
      return res.status(403).json({ success: false, message: 'Not authorized to view this batch' });
    }

    res.status(200).json({ success: true, data: batch });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Log a new harvest batch
// @route   POST /api/v1/inventory
// @access  Private (Farmer only)
const createInventoryBatch = async (req, res) => {
  try {
    const { product, quantity, harvestDate, expiryDate } = req.body;

    const batch = await InventoryBatch.create({
      product,
      farmer: req.user._id,
      quantity,
      harvestDate,
      expiryDate,
      status: 'Harvested'
    });

    res.status(201).json({ success: true, data: batch });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update inventory batch
// @route   PUT /api/v1/inventory/:id
// @access  Private (Farmer owner or Admin)
const updateInventoryBatch = async (req, res) => {
  try {
    let batch = await InventoryBatch.findById(req.params.id);
    if (!batch) {
      return res.status(404).json({ success: false, message: 'Batch not found' });
    }

    // Check ownership
    if (batch.farmer.toString() !== req.user._id.toString() && req.user.role !== 'admin') {
      return res.status(403).json({ success: false, message: 'Not authorized to update this batch' });
    }

    batch = await InventoryBatch.findByIdAndUpdate(req.params.id, req.body, {
      new: true,
      runValidators: true
    });

    res.status(200).json({ success: true, data: batch });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Delete inventory batch
// @route   DELETE /api/v1/inventory/:id
// @access  Private (Admin only)
const deleteInventoryBatch = async (req, res) => {
  try {
    const batch = await InventoryBatch.findById(req.params.id);
    if (!batch) {
      return res.status(404).json({ success: false, message: 'Batch not found' });
    }
    await batch.deleteOne();
    res.status(200).json({ success: true, message: 'Batch deleted successfully' });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get available inventory batches for buyers
// @route   GET /api/v1/inventory/available
// @access  Private (Buyer)
const getAvailableBatches = async (req, res) => {
  try {
    const { product } = req.query;
    if (!product) {
      return res.status(400).json({ success: false, message: 'Product is required' });
    }
    const batches = await InventoryBatch.find({
      product,
      status: 'Harvested',
      quantity: { $gt: 0 }
    })
      .populate('product', 'name category unit')
      .populate('farmer', 'name email')
      .sort({ createdAt: -1 });
    res.status(200).json({ success: true, count: batches.length, data: batches });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

module.exports = { getInventory, getInventoryBatch, createInventoryBatch, updateInventoryBatch, deleteInventoryBatch, getAvailableBatches };