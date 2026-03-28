const Order = require('../models/Order');
const InventoryBatch = require('../models/InventoryBatch');
const Product = require('../models/Product');

// @desc    Get all orders (admin) or own orders (buyer)
// @route   GET /api/v1/orders
// @access  Private (Admin or Buyer)
const getOrders = async (req, res) => {
  try {
    let query = {};
    if (req.user.role === 'buyer') query.buyer = req.user._id;

    const orders = await Order.find(query)
      .populate('buyer', 'name email')
      .populate('product', 'name category pricePerUnit unit')
      .populate('inventoryBatch', 'batchCode quantity status')
      .sort({ createdAt: -1 });

    res.status(200).json({ success: true, count: orders.length, data: orders });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Place a new order
// @route   POST /api/v1/orders
// @access  Private (Buyer only)
const createOrder = async (req, res) => {
  try {
    const { product, inventoryBatch, quantityOrdered } = req.body;

    // Check if product exists and is approved
    const productDoc = await Product.findById(product);
    if (!productDoc || !productDoc.isApproved) {
      return res.status(404).json({ success: false, message: 'Product not found or not approved' });
    }

    // Check if batch has enough stock
    const batch = await InventoryBatch.findById(inventoryBatch);
    if (!batch) {
      return res.status(404).json({ success: false, message: 'Inventory batch not found' });
    }
    if (batch.quantity < quantityOrdered) {
      return res.status(400).json({ success: false, message: 'Insufficient stock in selected batch' });
    }

    // Calculate total price
    const totalPrice = productDoc.pricePerUnit * quantityOrdered;

    // Create order
    const order = await Order.create({
      buyer: req.user._id,
      product,
      inventoryBatch,
      quantityOrdered,
      totalPrice
    });

    // Deduct quantity from batch
    batch.quantity -= quantityOrdered;
    if (batch.quantity === 0) batch.status = 'Sold';
    await batch.save();

    res.status(201).json({ success: true, data: order });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update order status
// @route   PUT /api/v1/orders/:id/status
// @access  Private (Admin only)
const updateOrderStatus = async (req, res) => {
  try {
    const { status } = req.body;
    const validStatuses = ['Pending', 'Confirmed', 'Completed', 'Cancelled'];

    if (!validStatuses.includes(status)) {
      return res.status(400).json({ success: false, message: 'Invalid status value' });
    }

    const order = await Order.findByIdAndUpdate(
      req.params.id,
      { status },
      { new: true, runValidators: true }
    );

    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    res.status(200).json({ success: true, data: order });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get single order
// @route   GET /api/v1/orders/:id
// @access  Private (Admin or Buyer owner)
const getOrder = async (req, res) => {
  try {
    const order = await Order.findById(req.params.id)
      .populate('buyer', 'name email')
      .populate('product', 'name category pricePerUnit unit')
      .populate('inventoryBatch', 'batchCode quantity status');

    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    // Buyers can only view their own orders
    if (req.user.role === 'buyer' && order.buyer._id.toString() !== req.user._id.toString()) {
      return res.status(403).json({ success: false, message: 'Not authorized to view this order' });
    }

    res.status(200).json({ success: true, data: order });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

module.exports = { getOrders, createOrder, updateOrderStatus, getOrder };