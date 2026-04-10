// Run this script with: node server/scripts/cleanupOrphanedOrders.js
require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const mongoose = require('mongoose');
const Order = require('../models/Order');
const Product = require('../models/Product');
const User = require('../models/User');
const db = require('../config/db');

(async () => {
  try {
    await db(); // Connect to DB
    console.log('Connected to DB');

    // Find all orders
    const orders = await Order.find({}).populate('buyer').populate('product');
    let toDelete = [];

    for (const order of orders) {
      if (!order.buyer || !order.product) {
        toDelete.push(order._id);
      }
    }

    if (toDelete.length > 0) {
      await Order.deleteMany({ _id: { $in: toDelete } });
      console.log(`Deleted ${toDelete.length} orphaned orders.`);
    } else {
      console.log('No orphaned orders found.');
    }
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
})();
