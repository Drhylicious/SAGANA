// @desc    Get all products for the authenticated farmer (approved and pending)
// @route   GET /api/v1/products/mine
// @access  Private (Farmer only)
const getMyProducts = async (req, res) => {
  try {
    const { category, page = 1, limit = 100, sort } = req.query;
    const query = { farmer: req.user._id };
    if (category) query.category = category;

    const products = await Product.find(query)
      .populate('farmer', 'name email')
      .sort(sort ? { [sort]: 1 } : { createdAt: -1 })
      .limit(limit * 1)
      .skip((page - 1) * limit);

    res.status(200).json({ success: true, count: products.length, data: products });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
// @desc    Get products with recent price drops
// @route   GET /api/v1/products/price-drops
// @access  Public
const getPriceDropProducts = async (req, res) => {
  try {
    const days = parseInt(req.query.days) || 7;
    const sinceDate = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    // Find products where the last priceHistory entry is a drop within the period
    const products = await Product.find({
      isApproved: true,
      priceHistory: { $exists: true, $not: { $size: 0 } }
    }).populate('farmer', 'name email');

    // Filter for products with a price drop in the last X days (any drop, not just last two)
    const priceDropProducts = products.filter(product => {
      if (!product.priceHistory || product.priceHistory.length < 2) {
        console.log(`[PriceDrop] ${product.name}: Not enough price history.`);
        return false;
      }
      const history = product.priceHistory;
      let found = false;
      for (let i = 1; i < history.length; i++) {
        if (
          history[i].price < history[i - 1].price &&
          new Date(history[i].date) >= sinceDate
        ) {
          found = true;
          break;
        }
      }
      if (found) {
        console.log(`[PriceDrop] ${product.name}: Price drop detected! History:`, history);
      } else {
        console.log(`[PriceDrop] ${product.name}: No recent price drop. History:`, history);
      }
      return found;
    });

    res.status(200).json({ success: true, count: priceDropProducts.length, data: priceDropProducts });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
const Product = require('../models/Product');

// @desc    Get all approved products (public marketplace)
// @route   GET /api/v1/products
// @access  Public
const getProducts = async (req, res) => {
  try {
    const { category, page = 1, limit = 10, sort } = req.query;
    const query = { isApproved: true };
    if (category) query.category = category;

    const products = await Product.find(query)
      .populate('farmer', 'name email')
      .sort(sort ? { [sort]: 1 } : { createdAt: -1 })
      .limit(limit * 1)
      .skip((page - 1) * limit);

    res.status(200).json({ success: true, count: products.length, data: products });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get single product
// @route   GET /api/v1/products/:id
// @access  Public
const getProduct = async (req, res) => {
  try {
    const product = await Product.findById(req.params.id).populate('farmer', 'name email');
    if (!product) {
      return res.status(404).json({ success: false, message: 'Product not found' });
    }
    res.status(200).json({ success: true, data: product });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Create a product
// @route   POST /api/v1/products
// @access  Private (Farmer only)
const createProduct = async (req, res) => {
  try {
    const { name, category, description, pricePerUnit, unit } = req.body;
    let imagePath = undefined;
    if (req.file) {
      imagePath = `/uploads/${req.file.filename}`;
    }
    // Allow image to be optional in test environment
    const product = await Product.create({
      farmer: req.user._id,
      name,
      category,
      description,
      pricePerUnit,
      unit,
      image: imagePath,
      isApproved: false, // Always require admin approval
      priceHistory: [{ price: pricePerUnit, date: new Date() }]
    });
    res.status(201).json({ success: true, data: product });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update a product
// @route   PUT /api/v1/products/:id
// @access  Private (Farmer owner or Admin)
const fs = require('fs');
const path = require('path');
const updateProduct = async (req, res) => {
  try {
    let product = await Product.findById(req.params.id);
    if (!product) {
      return res.status(404).json({ success: false, message: 'Product not found' });
    }

    // Check ownership
    if (product.farmer.toString() !== req.user._id.toString() && req.user.role !== 'admin') {
      return res.status(403).json({ success: false, message: 'Not authorized to update this product' });
    }

    // If pricePerUnit is being updated and is different, push to priceHistory
    if (
      req.body.pricePerUnit !== undefined &&
      req.body.pricePerUnit !== product.pricePerUnit
    ) {
      product.priceHistory = product.priceHistory || [];
      product.priceHistory.push({ price: req.body.pricePerUnit, date: new Date() });
    }

    // If a new image is uploaded, delete the old one and update path
    if (req.file) {
      if (product.image) {
        const oldPath = path.join(__dirname, '..', product.image);
        fs.unlink(oldPath, (err) => {}); // Delete old image (ignore errors)
      }
      product.image = `/uploads/${req.file.filename}`;
    }

    // Update product fields
    Object.assign(product, req.body);
    await product.save();
    res.status(200).json({ success: true, data: product });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Approve a product
// @route   PUT /api/v1/products/:id/approve
// @access  Private (Admin only)
const approveProduct = async (req, res) => {
  try {
    const product = await Product.findByIdAndUpdate(
      req.params.id,
      { isApproved: true },
      { new: true }
    );
    if (!product) {
      return res.status(404).json({ success: false, message: 'Product not found' });
    }
    res.status(200).json({ success: true, data: product });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Delete a product
// @route   DELETE /api/v1/products/:id
// @access  Private (Farmer owner or Admin)
const deleteProduct = async (req, res) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) {
      return res.status(404).json({ success: false, message: 'Product not found' });
    }
    // Only allow delete if admin or owner
    if (
      req.user.role !== 'admin' &&
      product.farmer.toString() !== req.user._id.toString()
    ) {
      return res.status(403).json({ success: false, message: 'Not authorized to delete this product' });
    }
    await product.deleteOne();
    res.status(200).json({ success: true, message: 'Product deleted successfully' });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get all products (admin)
// @route   GET /api/v1/products/all
// @access  Private (Admin only)
const getAllProducts = async (req, res) => {
  try {
    const { category, page = 1, limit = 100, sort } = req.query;
    const query = {};
    if (category) query.category = category;

    const products = await Product.find(query)
      .populate('farmer', 'name email')
      .sort(sort ? { [sort]: 1 } : { createdAt: -1 })
      .limit(limit * 1)
      .skip((page - 1) * limit);

    res.status(200).json({ success: true, count: products.length, data: products });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

module.exports = { getProducts, getProduct, createProduct, updateProduct, approveProduct, deleteProduct, getAllProducts, getPriceDropProducts, getMyProducts };