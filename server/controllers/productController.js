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
    const product = await Product.create({
      farmer: req.user._id,
      name,
      category,
      description,
      pricePerUnit,
      unit
    });
    res.status(201).json({ success: true, data: product });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update a product
// @route   PUT /api/v1/products/:id
// @access  Private (Farmer owner or Admin)
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

    product = await Product.findByIdAndUpdate(req.params.id, req.body, {
      new: true, runValidators: true
    });
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
// @access  Private (Admin only)
const deleteProduct = async (req, res) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) {
      return res.status(404).json({ success: false, message: 'Product not found' });
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

module.exports = { getProducts, getProduct, createProduct, updateProduct, approveProduct, deleteProduct, getAllProducts };