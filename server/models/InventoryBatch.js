const mongoose = require('mongoose');

const inventoryBatchSchema = new mongoose.Schema({
  product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
  farmer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  quantity: { type: Number, required: true, min: 0 },
  harvestDate: { type: Date, required: true },
  expiryDate: { type: Date, required: true },
  status: { type: String, enum: ['Harvested', 'Stored', 'Listed', 'Sold', 'Expired'], default: 'Harvested' },
  batchCode: { type: String, unique: true }
}, { timestamps: true });

// Auto-generate batch code before saving
inventoryBatchSchema.pre('save', async function() {
  if (!this.batchCode) {
    const date = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    this.batchCode = `BCH-${date}-${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}`;
  }
});

module.exports = mongoose.model('InventoryBatch', inventoryBatchSchema);