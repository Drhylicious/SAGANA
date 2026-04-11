const Product = require('../models/Product');

// @desc    Get crop analytics for predictive planting calendar
// @route   GET /api/v1/inventory/analytics?product=<productId>
// @access  Private (Farmer)
const getCropAnalytics = async (req, res) => {
  try {
    const { product } = req.query;
    if (!product) {
      return res.status(400).json({ success: false, message: 'Product ID is required' });
    }

    // Only show batches for this farmer and product
    const batches = await InventoryBatch.find({
      product,
      farmer: req.user._id,
      status: { $in: ['Harvested', 'Stored', 'Listed', 'Sold'] }
    });

    if (!batches.length) {
      return res.status(200).json({
        success: true,
        data: null,
        message: 'No harvest data available for this crop.'
      });
    }

    // Calculate growth durations using plantingDate (days between harvestDate and plantingDate)
    const growthDurations = batches.map(b => {
      const planted = b.plantingDate || new Date(b.harvestDate.getTime() - 90 * 24 * 60 * 60 * 1000); // default 90 days before harvest
      return (new Date(b.harvestDate) - planted) / (1000 * 60 * 60 * 24);
    }).filter(d => d > 0 && d < 365); // reasonable crop growth 1-365 days

    const avgGrowthDuration = growthDurations.length
      ? Math.round(growthDurations.reduce((a, b) => a + b, 0) / growthDurations.length)
      : null;


    // Group harvests by month
    const monthlyYields = Array(12).fill(0);
    batches.forEach(b => {
      const month = new Date(b.harvestDate).getMonth();
      monthlyYields[month] += b.quantity;
    });

    // Find optimal harvest window (months with highest yields)
    const maxYield = Math.max(...monthlyYields);
    const optimalHarvestMonths = monthlyYields
      .map((val, idx) => (val === maxYield ? idx : null))
      .filter(idx => idx !== null);

    // Estimate optimal planting window (harvest month - avg growth duration)
    let optimalPlantingMonths = [];
    if (avgGrowthDuration !== null) {
      optimalPlantingMonths = optimalHarvestMonths.map(hMonth => {
        let pMonth = hMonth - Math.round(avgGrowthDuration / 30);
        if (pMonth < 0) pMonth += 12;
        return pMonth;
      });
    }

    // Get product name
    const prod = await Product.findById(product);

    res.status(200).json({
      success: true,
      data: {
        product: prod ? prod.name : '',
        avgGrowthDuration,
        optimalHarvestMonths,
        optimalPlantingMonths,
        monthlyYields
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
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

module.exports = { getInventory, getInventoryBatch, createInventoryBatch, updateInventoryBatch, deleteInventoryBatch, getAvailableBatches, getCropAnalytics };