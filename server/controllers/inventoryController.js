
const InventoryBatch = require('../models/InventoryBatch');
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

    const batches = await InventoryBatch.find({ product, farmer: req.user._id });
    const prod = await Product.findById(product);

    if (!batches.length) {
      return res.status(200).json({
        success: true,
        data: {
          product: prod ? prod.name : '',
          avgGrowthDuration: null,
          optimalHarvestMonths: [],
          optimalPlantingMonths: [],
          monthlyYields: Array(12).fill(0),
          predictiveScores: Array(12).fill(0)
        },
        message: 'No harvest data yet for this crop.'
      });
    }

    // ── ACTUAL HARVEST DATA ────────────────────────────────
    const monthlyYields = Array(12).fill(0);
    batches.forEach(b => {
      const month = new Date(b.harvestDate).getMonth();
      monthlyYields[month] += b.quantity;
    });

    // ── AVERAGE GROWTH DURATION ────────────────────────────
    const growthDurations = batches.map(b => {
      if (b.harvestDate && b.expiryDate) {
        const diff = (new Date(b.expiryDate) - new Date(b.harvestDate)) / (1000 * 60 * 60 * 24);
        return diff > 0 && diff < 365 ? diff : 90;
      }
      return 90;
    });
    const avgGrowthDuration = Math.round(
      growthDurations.reduce((a, b) => a + b, 0) / growthDurations.length
    );

    // ── OPTIMAL WINDOWS ────────────────────────────────────
    const sorted = monthlyYields
      .map((val, idx) => ({ val, idx }))
      .sort((a, b) => b.val - a.val);
    const optimalHarvestMonths = sorted.slice(0, 3).filter(m => m.val > 0).map(m => m.idx);
    const optimalPlantingMonths = optimalHarvestMonths.map(hMonth => {
      let pMonth = hMonth - Math.round(avgGrowthDuration / 30);
      if (pMonth < 0) pMonth += 12;
      return pMonth;
    });

    // ── PREDICTIVE YIELD SCORE (0-100) ─────────────────────
    // Step 1: Normalize actual yields to 0-100 base score
    const maxYield = Math.max(...monthlyYields, 1);
    const normalizedScores = monthlyYields.map(y => (y / maxYield) * 100);

    // Step 2: Apply 3-month weighted moving average for smoothing
    const smoothed = normalizedScores.map((score, i) => {
      const prev = normalizedScores[(i - 1 + 12) % 12];
      const next = normalizedScores[(i + 1) % 12];
      return (prev * 0.25 + score * 0.5 + next * 0.25);
    });

    // Step 3: Boost months adjacent to peak harvest months
    // (months before peak = good planting, months of peak = good harvest)
    const boosted = smoothed.map((score, i) => {
      const isNearPeak = optimalHarvestMonths.some(peak => {
        const dist = Math.min(Math.abs(i - peak), 12 - Math.abs(i - peak));
        return dist <= 1;
      });
      return isNearPeak ? Math.min(score * 1.3, 100) : score;
    });

    // Step 4: Apply seasonal trend factor based on Marinduque climate
    // Wet season (Jun-Oct) slightly reduces field work productivity
    // Dry season (Nov-May) is generally better for most crops
    const seasonalFactor = [1.05, 1.05, 1.05, 1.0, 1.0, 0.9, 0.85, 0.85, 0.9, 0.95, 1.0, 1.05];
    const predictiveScores = boosted.map((score, i) =>
      Math.min(Math.round(score * seasonalFactor[i]), 100)
    );

    res.status(200).json({
      success: true,
      data: {
        product: prod ? prod.name : '',
        avgGrowthDuration,
        optimalHarvestMonths,
        optimalPlantingMonths,
        monthlyYields,
        predictiveScores  // ← NEW separate from monthlyYields
      }
    });
  } catch (error) {
    console.error('getCropAnalytics error:', error.message);
    res.status(500).json({ success: false, message: error.message });
  }
};


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