import { useState, useEffect, useRef } from 'react';
import API from '../api/axios';
import { useAuth } from '../context/AuthContext';
import PageWrapper from '../components/PageWrapper';
import AnalyticsLineChart from '../components/AnalyticsLineChart';

const FarmerDashboard = () => {
  const { user } = useAuth();
  const [products, setProducts] = useState([]);
  const [inventory, setInventory] = useState([]);
  const [activeTab, setActiveTab] = useState('products');
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [productForm, setProductForm] = useState({
    name: '', category: 'Vegetable', description: '', pricePerUnit: '', unit: ''
  });
  const [editingProduct, setEditingProduct] = useState(null);
  const [imageFile, setImageFile] = useState(null);
  const [imagePreview, setImagePreview] = useState(null);
  const fileInputRef = useRef(null);
  const [inventoryForm, setInventoryForm] = useState({
    product: '', quantity: '', harvestDate: '', expiryDate: ''
  });
  const [selectedProductId, setSelectedProductId] = useState('');
  const [analytics, setAnalytics] = useState(null);
  const [analyticsLoading, setAnalyticsLoading] = useState(false);
  const [analyticsError, setAnalyticsError] = useState('');

  const statusColors = {
    Stored: 'bg-blue-100 text-blue-700',
    Listed: 'bg-purple-100 text-purple-700',
    Sold: 'bg-gray-100 text-gray-700',
    Expired: 'bg-red-100 text-red-700',
    Harvested: 'bg-green-100 text-green-700',
  };

  const tabIcons = {
    products: '🧺',
    inventory: '📦',
    'add-product': '➕',
    'add-inventory': '🌱',
    analytics: '📊',
  };

  // ── FETCH DATA ─────────────────────────────────────────
  const refreshData = async () => {
    setLoading(true);
    try {
      const [productsRes, inventoryRes] = await Promise.all([
        API.get('/products/mine'),
        API.get('/inventory'),
      ]);
      setProducts(Array.isArray(productsRes.data?.data) ? productsRes.data.data : []);
      setInventory(Array.isArray(inventoryRes.data?.data) ? inventoryRes.data.data : []);
    } catch (error) {
      setMessage('❌ Failed to refresh data');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    refreshData();
  }, []);

  // ── ANALYTICS FETCH ────────────────────────────────────
  useEffect(() => {
    if (!selectedProductId) {
      setAnalytics(null);
      setAnalyticsError('');
      return;
    }
    setAnalyticsLoading(true);
    setAnalyticsError('');
    API.get(`/inventory/analytics?product=${selectedProductId}`)
      .then(res => {
        setAnalytics(res.data?.data || null);
        setAnalyticsError(res.data?.message || '');
      })
      .catch(() => {
        setAnalytics(null);
        setAnalyticsError('Failed to load analytics');
      })
      .finally(() => setAnalyticsLoading(false));
  }, [selectedProductId]);

  // ── HANDLERS ───────────────────────────────────────────
  const handleCreateProduct = async (e) => {
    e.preventDefault();
    setMessage('');
    try {
      const formData = new FormData();
      formData.append('name', productForm.name);
      formData.append('category', productForm.category);
      formData.append('description', productForm.description);
      formData.append('pricePerUnit', productForm.pricePerUnit);
      formData.append('unit', productForm.unit);
      if (imageFile) formData.append('image', imageFile);

      if (editingProduct) {
        await API.put(`/products/${editingProduct._id}`, formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        });
        setMessage('✅ Product updated!');
      } else {
        await API.post('/products', formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        });
        setMessage('✅ Product submitted for approval!');
      }
      setProductForm({ name: '', category: 'Vegetable', description: '', pricePerUnit: '', unit: '' });
      setImageFile(null);
      setImagePreview(null);
      setEditingProduct(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
      await refreshData();
    } catch (err) {
      setMessage('❌ Failed to submit product.');
    }
  };

  const handleCreateInventory = async (e) => {
    e.preventDefault();
    setMessage('');
    try {
      await API.post('/inventory', {
        product: inventoryForm.product,
        quantity: inventoryForm.quantity,
        harvestDate: inventoryForm.harvestDate,
        expiryDate: inventoryForm.expiryDate,
      });
      setMessage('✅ Harvest batch logged!');
      setInventoryForm({ product: '', quantity: '', harvestDate: '', expiryDate: '' });
      await refreshData();
    } catch (err) {
      setMessage('❌ Failed to log harvest batch.');
    }
  };

  const handleEditProduct = (product) => {
    setEditingProduct(product);
    setProductForm({
      name: product.name || '',
      category: product.category || 'Vegetable',
      description: product.description || '',
      pricePerUnit: product.pricePerUnit || '',
      unit: product.unit || '',
    });
    setImageFile(null);
    setImagePreview(product.image || null);
    setActiveTab('add-product');
    setMessage('');
  };

  const handleDeleteProduct = async (id) => {
    if (!window.confirm('Delete this product?')) return;
    setMessage('');
    try {
      await API.delete(`/products/${id}`);
      setMessage('✅ Product deleted.');
      await refreshData();
    } catch (err) {
      setMessage('❌ Failed to delete product.');
    }
  };

  // ── COMPUTED VALUES ────────────────────────────────────
  const myProducts = products;
  const approvedProducts = myProducts.filter(p => p.isApproved);
  const pendingProducts = myProducts.filter(p => !p.isApproved);
  const inventoryValue = inventory.reduce((sum, batch) => {
    const prod = products.find(p => p._id === (batch.product?._id || batch.product));
    return sum + (prod ? prod.pricePerUnit * batch.quantity : 0);
  }, 0);

  if (loading) return <div className="text-center py-20 text-gray-400">Loading...</div>;

  return (
    <PageWrapper>
      <div className="max-w-6xl mx-auto px-4 py-8">
        <h1 className="text-3xl font-bold text-primary mb-2 flex items-center gap-2">
          Farmer Dashboard <span className="text-2xl">👨‍🌾</span>
        </h1>
        <p className="text-gray-500 mb-6">Welcome back, {user?.name}! 🌾</p>

        {/* Quick Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">🧺</span>
            <div className="text-lg font-bold">{myProducts.length}</div>
            <div className="text-xs text-gray-500">My Products</div>
          </div>
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">✅</span>
            <div className="text-lg font-bold">{approvedProducts.length}</div>
            <div className="text-xs text-gray-500">Approved</div>
          </div>
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">⏳</span>
            <div className="text-lg font-bold">{pendingProducts.length}</div>
            <div className="text-xs text-gray-500">Pending</div>
          </div>
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">💰</span>
            <div className="text-lg font-bold">₱{inventoryValue.toLocaleString()}</div>
            <div className="text-xs text-gray-500">Inventory Value</div>
          </div>
        </div>

        {message && (
          <div className="mb-4 px-4 py-3 rounded-lg bg-gray-100 text-sm">{message}</div>
        )}

        {/* Tabs */}
        <div className="flex gap-2 mb-6 flex-wrap">
          {['products', 'inventory', 'add-product', 'add-inventory', 'analytics'].map((tab) => (
            <button
              key={tab}
              onClick={() => { setActiveTab(tab); setMessage(''); }}
              className={`px-4 py-2 rounded-lg font-semibold text-sm transition flex items-center gap-2 ${
                activeTab === tab
                  ? 'bg-primary text-white'
                  : 'bg-white text-gray-600 border hover:border-primary'
              }`}
            >
              <span>{tabIcons[tab]}</span>
              {tab === 'add-product' ? 'Add Product'
                : tab === 'add-inventory' ? 'Log Harvest'
                : tab === 'analytics' ? 'Analytics'
                : tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </div>

        {/* Analytics Tab */}
        {activeTab === 'analytics' && (
          <div className="bg-white rounded-xl shadow border p-0 mb-8">
            <div className="rounded-t-xl bg-green-700 px-6 py-4 flex flex-col gap-2">
              <h2 className="text-lg font-bold text-white flex items-center gap-2">Marinduque Smart Planting Calendar</h2>
              <p className="text-green-100 text-sm">Optimize your crop yields with data-driven predictive analytics based on Marinduque soil data, weather patterns, and historical climate conditions.</p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 px-6 py-4">
              <div className="bg-white rounded-lg shadow p-4 flex flex-col items-center border">
                <div className="text-green-700 text-2xl font-bold">{inventory.length}</div>
                <div className="text-xs text-gray-500 mt-1">Total Batches Logged</div>
              </div>
              <div className="bg-white rounded-lg shadow p-4 flex flex-col items-center border">
                <div className="text-green-700 text-2xl font-bold">{inventory.reduce((sum, b) => sum + (b.quantity || 0), 0)} kg</div>
                <div className="text-xs text-gray-500 mt-1">Total Quantity Harvested</div>
              </div>
              <div className="bg-white rounded-lg shadow p-4 flex flex-col items-center border">
                <div className="text-green-700 text-2xl font-bold">{inventory.filter(b => b.status === 'Harvested').length}</div>
                <div className="text-xs text-gray-500 mt-1">Active Batches</div>
              </div>
            </div>
            <div className="px-6 pb-2">
              <label className="block text-sm font-semibold mb-1">Select Crop for Prediction</label>
              <select
                className="border rounded-lg px-4 py-2 min-w-[200px]"
                value={selectedProductId}
                onChange={e => setSelectedProductId(e.target.value)}
              >
                <option value="">-- Choose a crop --</option>
                {approvedProducts.map(p => (
                  <option key={p._id} value={p._id}>{p.name}</option>
                ))}
              </select>
            </div>
            {analyticsLoading && <div className="px-6 py-4 text-gray-400">Loading analytics...</div>}
            {analyticsError && !analyticsLoading && <div className="px-6 py-4 text-red-500 text-sm">{analyticsError}</div>}
            {analytics && (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 px-6 py-2">
                  <div className="bg-green-50 border-l-4 border-green-400 rounded p-4 flex flex-col items-center">
                    <div className="text-xs text-gray-500 mb-1">Optimal Planting Window</div>
                    <div className="font-bold text-green-700 text-lg">{analytics.optimalPlantingMonths?.length > 0
                      ? analytics.optimalPlantingMonths.map(m => new Date(2000, m).toLocaleString('default', { month: 'short' })).join(', ')
                      : 'N/A'}</div>
                  </div>
                  <div className="bg-blue-50 border-l-4 border-blue-400 rounded p-4 flex flex-col items-center">
                    <div className="text-xs text-gray-500 mb-1">Predicted Growth Duration</div>
                    <div className="font-bold text-blue-700 text-lg">{analytics.avgGrowthDuration ? `${analytics.avgGrowthDuration} days` : 'N/A'}</div>
                  </div>
                  <div className="bg-yellow-50 border-l-4 border-yellow-400 rounded p-4 flex flex-col items-center">
                    <div className="text-xs text-gray-500 mb-1">Optimal Harvest Window</div>
                    <div className="font-bold text-yellow-700 text-lg">{analytics.optimalHarvestMonths?.length > 0
                      ? analytics.optimalHarvestMonths.map(m => new Date(2000, m).toLocaleString('default', { month: 'short' })).join(', ')
                      : 'N/A'}</div>
                  </div>
                </div>
                {/* Predictive Yield Score */}
                <div className="px-6 pt-4">
                  <div className="font-semibold mb-1">📊 Predictive Yield Score — {analytics.product}</div>
                  <p className="text-xs text-gray-400 mb-2 px-0">
                    Predicted yield potential (0–100) based on your harvest history, seasonal patterns, and Marinduque climate data
                  </p>
                  <AnalyticsLineChart data={analytics.predictiveScores} maxValue={100} />
                </div>

                {/* Actual Harvest History */}
                <div className="px-6 pt-4">
                  <div className="font-semibold mb-1">📦 Your Actual Harvest History — {analytics.product}</div>
                  <p className="text-xs text-gray-400 mb-2">
                    Real quantities harvested per month from your inventory records
                  </p>
                  <AnalyticsLineChart data={analytics.monthlyYields} />
                </div>
                <div className="px-6 pt-4 pb-6">
                  <div className="font-semibold mb-1">Recent Harvest Batches</div>
                  <div className="overflow-x-auto">
                    <table className="min-w-full text-sm border">
                      <thead className="bg-gray-50 text-gray-600">
                        <tr>
                          <th className="px-3 py-2 text-left">Batch Code</th>
                          <th className="px-3 py-2 text-left">Product</th>
                          <th className="px-3 py-2 text-left">Quantity</th>
                          <th className="px-3 py-2 text-left">Harvest Date</th>
                          <th className="px-3 py-2 text-left">Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {inventory
                          .filter(b => b.product?._id === selectedProductId || b.product === selectedProductId)
                          .sort((a, b) => new Date(b.harvestDate) - new Date(a.harvestDate))
                          .slice(0, 5)
                          .map(batch => (
                            <tr key={batch._id}>
                              <td className="px-3 py-2 font-mono text-xs">{batch.batchCode}</td>
                              <td className="px-3 py-2">{batch.product?.name || ''}</td>
                              <td className="px-3 py-2">{batch.quantity} {batch.product?.unit || ''}</td>
                              <td className="px-3 py-2">{new Date(batch.harvestDate).toLocaleDateString()}</td>
                              <td className="px-3 py-2">
                                <span className={`px-2 py-1 rounded-full text-xs font-medium ${statusColors[batch.status]}`}>{batch.status}</span>
                              </td>
                            </tr>
                          ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              </>
            )}
          </div>
        )}

        {/* My Products */}
        {activeTab === 'products' && (
          <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-600">
                <tr>
                  <th className="text-left px-4 py-3">Image</th>
                  <th className="text-left px-4 py-3">Product</th>
                  <th className="text-left px-4 py-3">Category</th>
                  <th className="text-left px-4 py-3">Price</th>
                  <th className="text-left px-4 py-3">Status</th>
                  <th className="text-left px-4 py-3">Actions</th>
                </tr>
              </thead>
              <tbody>
                {myProducts.map((product) => (
                  <tr key={product._id} className="border-t hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <span className="text-2xl">
                        {product.category === 'Vegetable' ? '🥦'
                          : product.category === 'Fruit' ? '🍎'
                          : product.category === 'Grain' ? '🌾'
                          : product.category === 'Spice' ? '🌶️'
                          : product.category === 'Fresh Meat' ? '🥩'
                          : product.category === 'Seafood' ? '🐟'
                          : '📦'}
                      </span>
                    </td>
                    <td className="px-4 py-3 font-medium">{product.name}</td>
                    <td className="px-4 py-3 text-gray-500">{product.category}</td>
                    <td className="px-4 py-3">₱{product.pricePerUnit}/{product.unit}</td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                        product.isApproved ? 'bg-green-100 text-green-700' : 'bg-yellow-100 text-yellow-700'
                      }`}>
                        {product.isApproved ? 'Approved' : 'Pending Approval'}
                      </span>
                    </td>
                    <td className="px-4 py-3 flex gap-2">
                      <button className="px-2 py-1 text-xs rounded bg-blue-100 text-blue-700 hover:bg-blue-200 transition" onClick={() => handleEditProduct(product)}>✏️ Edit</button>
                      <button className="px-2 py-1 text-xs rounded bg-red-100 text-red-700 hover:bg-red-200 transition" onClick={() => handleDeleteProduct(product._id)}>🗑️ Delete</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Inventory */}
        {activeTab === 'inventory' && (
          <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-600">
                <tr>
                  <th className="text-left px-4 py-3">Batch Code</th>
                  <th className="text-left px-4 py-3">Product</th>
                  <th className="text-left px-4 py-3">Quantity</th>
                  <th className="text-left px-4 py-3">Expiry</th>
                  <th className="text-left px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {inventory.map((batch) => (
                  <tr key={batch._id} className="border-t hover:bg-gray-50">
                    <td className="px-4 py-3 font-mono text-xs">{batch.batchCode}</td>
                    <td className="px-4 py-3 font-medium">{batch.product?.name}</td>
                    <td className="px-4 py-3">{batch.quantity} {batch.product?.unit}</td>
                    <td className="px-4 py-3 text-gray-500">{new Date(batch.expiryDate).toLocaleDateString()}</td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${statusColors[batch.status]}`}>
                        {batch.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Add Product Form */}
        {activeTab === 'add-product' && (
          <div className="bg-white rounded-xl shadow-sm border p-6 max-w-lg">
            <h2 className="text-xl font-bold text-gray-800 mb-4">{editingProduct ? 'Edit Product' : 'Submit New Product'}</h2>
            <form onSubmit={handleCreateProduct} className="space-y-4" encType="multipart/form-data">
              <div>
                <label className="block font-semibold mb-1">Product Image <span className="text-red-500">*</span></label>
                {imagePreview && (
                  <img src={imagePreview} alt="Preview" className="mb-2 w-32 h-32 object-cover rounded border" />
                )}
                <input
                  type="file"
                  accept="image/*"
                  ref={fileInputRef}
                  required={!editingProduct}
                  onChange={e => {
                    const file = e.target.files[0];
                    setImageFile(file);
                    setImagePreview(file ? URL.createObjectURL(file) : null);
                  }}
                  className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
                />
              </div>
              <input type="text" placeholder="Product Name" required
                value={productForm.name}
                onChange={(e) => setProductForm({ ...productForm, name: e.target.value })}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              />
              <select value={productForm.category}
                onChange={(e) => setProductForm({ ...productForm, category: e.target.value })}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              >
                {['Vegetable', 'Fruit', 'Grain', 'Spice', 'Fresh Meat', 'Seafood', 'Other'].map(c => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
              <textarea placeholder="Description (optional)" rows={3}
                value={productForm.description}
                onChange={(e) => setProductForm({ ...productForm, description: e.target.value })}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              />
              <div className="flex gap-3">
                <input type="number" placeholder="Price per unit (₱)" required
                  value={productForm.pricePerUnit}
                  onChange={(e) => setProductForm({ ...productForm, pricePerUnit: e.target.value })}
                  className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
                />
                <input type="text" placeholder="Unit (kg, bundle...)" required
                  value={productForm.unit}
                  onChange={(e) => setProductForm({ ...productForm, unit: e.target.value })}
                  className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
                />
              </div>
              <button type="submit"
                className="w-full bg-primary text-white py-2 rounded-lg hover:bg-secondary transition font-semibold"
              >
                {editingProduct ? 'Update Product' : 'Submit for Approval'}
              </button>
              {editingProduct && (
                <button type="button"
                  className="w-full bg-gray-200 text-gray-700 py-2 rounded-lg mt-2 hover:bg-gray-300 transition font-semibold"
                  onClick={() => {
                    setEditingProduct(null);
                    setProductForm({ name: '', category: 'Vegetable', description: '', pricePerUnit: '', unit: '' });
                    setMessage('');
                  }}
                >
                  Cancel Edit
                </button>
              )}
            </form>
          </div>
        )}

        {/* Log Harvest Form */}
        {activeTab === 'add-inventory' && (
          <div className="bg-white rounded-xl shadow-sm border p-6 max-w-lg">
            <h2 className="text-xl font-bold text-gray-800 mb-4">Log Harvest Batch</h2>
            <form onSubmit={handleCreateInventory} className="space-y-4">
              <select required
                value={inventoryForm.product}
                onChange={(e) => setInventoryForm({ ...inventoryForm, product: e.target.value })}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              >
                <option value="">Select Product</option>
                {products.filter(p => p.isApproved).map(p => (
                  <option key={p._id} value={p._id}>{p.name}</option>
                ))}
              </select>
              <input type="number" placeholder="Quantity" required
                value={inventoryForm.quantity}
                onChange={(e) => setInventoryForm({ ...inventoryForm, quantity: e.target.value })}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              />
              <div className="flex gap-3">
                <div className="w-full">
                  <label className="text-xs text-gray-500 mb-1 block">Harvest Date</label>
                  <input type="date" required
                    value={inventoryForm.harvestDate}
                    onChange={(e) => setInventoryForm({ ...inventoryForm, harvestDate: e.target.value })}
                    className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
                  />
                </div>
                <div className="w-full">
                  <label className="text-xs text-gray-500 mb-1 block">Expiry Date</label>
                  <input type="date" required
                    value={inventoryForm.expiryDate}
                    onChange={(e) => setInventoryForm({ ...inventoryForm, expiryDate: e.target.value })}
                    className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
                  />
                </div>
              </div>
              <button type="submit"
                className="w-full bg-primary text-white py-2 rounded-lg hover:bg-secondary transition font-semibold"
              >
                Log Harvest Batch
              </button>
            </form>
          </div>
        )}

      </div>
    </PageWrapper>
  );
};

export default FarmerDashboard;