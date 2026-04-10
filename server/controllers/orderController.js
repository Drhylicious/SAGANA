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

// @desc    Edit order (quantity only, buyer only)
// @route   PUT /api/v1/orders/:id
// @access  Private (Buyer only, own order)
const editOrder = async (req, res) => {
  try {
    const { quantityOrdered } = req.body;
    if (!quantityOrdered || quantityOrdered < 1) {
      return res.status(400).json({ success: false, message: 'Quantity must be at least 1' });
    }

    const order = await Order.findById(req.params.id).populate('inventoryBatch').populate('product');
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }
    // Only buyer can edit their own order
    if (req.user.role !== 'buyer' || order.buyer.toString() !== req.user._id.toString()) {
      return res.status(403).json({ success: false, message: 'Not authorized to edit this order' });
    }

    // Only allow editing if order is not Cancelled/Completed/Confirmed
    if (["Cancelled", "Completed", "Confirmed"].includes(order.status)) {
      return res.status(400).json({ success: false, message: 'Cannot edit an order that is Confirmed, Completed, or Cancelled' });
    }

    const batch = await InventoryBatch.findById(order.inventoryBatch._id);
    if (!batch) {
      return res.status(404).json({ success: false, message: 'Inventory batch not found' });
    }

    // Restore previous quantity
    batch.quantity += order.quantityOrdered;
    // Check if enough stock for new quantity
    if (batch.quantity < quantityOrdered) {
      return res.status(400).json({ success: false, message: 'Insufficient stock in selected batch' });
    }
    // Deduct new quantity
    batch.quantity -= quantityOrdered;
    if (batch.quantity === 0) batch.status = 'Sold';
    else if (batch.status === 'Sold') batch.status = 'Listed';
    await batch.save();

    // Update order
    order.quantityOrdered = quantityOrdered;
    order.totalPrice = order.product.pricePerUnit * quantityOrdered;
    await order.save();

    res.status(200).json({ success: true, data: order });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Delete order (buyer: own, admin: any)
// @route   DELETE /api/v1/orders/:id
// @access  Private (Buyer own, Admin any)
const deleteOrder = async (req, res) => {
  try {
    const order = await Order.findById(req.params.id).populate('inventoryBatch');
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }
    // Buyer can only delete own order
    if (req.user.role === 'buyer' && order.buyer.toString() !== req.user._id.toString()) {
      return res.status(403).json({ success: false, message: 'Not authorized to delete this order' });
    }
    // Only allow deleting if order is not Confirmed/Completed
    if (["Confirmed", "Completed"].includes(order.status)) {
      return res.status(400).json({ success: false, message: 'Cannot delete an order that is Confirmed or Completed' });
    }
    // Restore quantity to batch
    if (order.inventoryBatch) {
      const batch = await InventoryBatch.findById(order.inventoryBatch._id);
      if (batch) {
        batch.quantity += order.quantityOrdered;
        if (batch.status === 'Sold') batch.status = 'Listed';
        await batch.save();
      }
    }
    await order.deleteOne();
    res.status(200).json({ success: true, message: 'Order deleted' });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

module.exports = { getOrders, createOrder, updateOrderStatus, getOrder, editOrder, deleteOrder };