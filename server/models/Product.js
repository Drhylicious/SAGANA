const mongoose = require('mongoose');

const productSchema = new mongoose.Schema({
  farmer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  name: { type: String, required: true },
  category: { type: String, enum: ['Vegetable', 'Fruit', 'Grain', 'Spice', 'Other'], required: true },
  description: { type: String },
  pricePerUnit: { type: Number, required: true, min: 0 },
  unit: { type: String, required: true },
  isApproved: { type: Boolean, default: false }
}, { timestamps: true });

module.exports = mongoose.model('Product', productSchema);