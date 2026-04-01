const mongoose = require('mongoose');

const productSchema = new mongoose.Schema({
  farmer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  name: { type: String, required: true },
  category: { type: String, enum: ['Vegetable', 'Fruit', 'Grain', 'Spice', 'Fresh Meat', 'Seafood', 'Other'], required: true },
  description: { type: String },
  pricePerUnit: { type: Number, required: true, min: 0 },
  unit: { type: String, required: true },
  isApproved: { type: Boolean, default: false },
  priceHistory: [
    {
      price: { type: Number },
      date: { type: Date, default: Date.now }
    }
  ],
  image: { type: String, required: true } // URL or path to product image
}, { timestamps: true });

module.exports = mongoose.model('Product', productSchema);