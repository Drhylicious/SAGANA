import { useState, useEffect, useRef } from 'react';
import API from '../api/axios';
import { useAuth } from '../context/AuthContext';
import PageWrapper from '../components/PageWrapper';

const FarmerDashboard = () => {
  const { user } = useAuth();
  const [products, setProducts] = useState([]);
  const [inventory, setInventory] = useState([]);
  const [activeTab, setActiveTab] = useState('products');
  const [loading, setLoading] = useState(true);
  const [productForm, setProductForm] = useState({
    name: '', category: 'Vegetable', description: '', pricePerUnit: '', unit: ''
  });
  const [imageFile, setImageFile] = useState(null);
  const [imagePreview, setImagePreview] = useState(null);
  const fileInputRef = useRef();
  const [inventoryForm, setInventoryForm] = useState({
    product: '', quantity: '', harvestDate: '', expiryDate: ''
  });
  const [message, setMessage] = useState('');
  const [editingProduct, setEditingProduct] = useState(null);

  useEffect(() => { fetchData(); }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const [productsRes, inventoryRes] = await Promise.all([
        API.get('/products/mine'),
        API.get('/inventory')
      ]);
      setProducts(productsRes.data.data);
      setInventory(inventoryRes.data.data);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };


  const handleCreateProduct = async (e) => {
    e.preventDefault();
    try {
      const formData = new FormData();
      formData.append('name', productForm.name);
      formData.append('category', productForm.category);
      formData.append('description', productForm.description);
      formData.append('pricePerUnit', productForm.pricePerUnit);
      formData.append('unit', productForm.unit);
      if (imageFile) formData.append('image', imageFile);

      if (editingProduct) {
        // Update existing product
        await API.put(`/products/${editingProduct._id}`, formData, {
          headers: { 'Content-Type': 'multipart/form-data' }
        });
        setMessage('✅ Product updated!');
        setEditingProduct(null);
      } else {
        // Create new product
        if (!imageFile) {
          setMessage('❌ Product image is required.');
          return;
        }
        await API.post('/products', formData, {
          headers: { 'Content-Type': 'multipart/form-data' }
        });
        setMessage('✅ Product submitted for admin approval!');
      }
      setProductForm({ name: '', category: 'Vegetable', description: '', pricePerUnit: '', unit: '' });
      setImageFile(null);
      setImagePreview(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
      fetchData();
    } catch (error) {
      setMessage('❌ ' + (error.response?.data?.message || 'Error creating/updating product'));
    }
  };

  const handleEditProduct = (product) => {
    setEditingProduct(product);
    setProductForm({
      name: product.name,
      category: product.category,
      description: product.description || '',
      pricePerUnit: product.pricePerUnit,
      unit: product.unit
    });
    setImageFile(null);
    setImagePreview(product.image ? `${import.meta.env.VITE_API_URL?.replace('/api/v1','') || 'http://localhost:5000' }${product.image}` : null);
    setActiveTab('add-product');
    setMessage('');
  };

  const handleDeleteProduct = async (productId) => {
    if (!window.confirm('Are you sure you want to delete this product?')) return;
    try {
      await API.delete(`/products/${productId}`);
      setMessage('✅ Product deleted!');
      fetchData();
    } catch (error) {
      setMessage('❌ ' + (error.response?.data?.message || 'Error deleting product'));
    }
  };

  const handleCreateInventory = async (e) => {
    e.preventDefault();
    try {
      await API.post('/inventory', inventoryForm);
      setMessage('✅ Harvest batch logged successfully!');
      setInventoryForm({ product: '', quantity: '', harvestDate: '', expiryDate: '' });
      fetchData();
    } catch (error) {
      setMessage('❌ ' + (error.response?.data?.message || 'Error logging batch'));
    }
  };

  const statusColors = {
    Harvested: 'bg-green-100 text-green-700',
    Stored: 'bg-blue-100 text-blue-700',
    Listed: 'bg-purple-100 text-purple-700',
    Sold: 'bg-gray-100 text-gray-700',
    Expired: 'bg-red-100 text-red-700',
  };

  if (loading) return <div className="text-center py-20 text-gray-400">Loading...</div>;


  // Quick stats
  const myProducts = products.filter(p => p.farmer?._id === user?._id || p.farmer === user?._id);
  const approvedProducts = myProducts.filter(p => p.isApproved);
  const pendingProducts = myProducts.filter(p => !p.isApproved);
  const inventoryValue = inventory.reduce((sum, batch) => {
    const prod = products.find(p => p._id === (batch.product?._id || batch.product));
    return sum + (prod ? prod.pricePerUnit * batch.quantity : 0);
  }, 0);

  // Tab icons
  const tabIcons = {
    products: '🧺',
    inventory: '📦',
    'add-product': '➕',
    'add-inventory': '🌱',
  };

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
        <div className="flex gap-2 mb-6">
          {['products', 'inventory', 'add-product', 'add-inventory'].map((tab) => (
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
                : tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </div>

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
                        {/* Use emoji based on category, fallback to 📦 */}
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
                    <td className="px-4 py-3 text-gray-500">
                      {new Date(batch.expiryDate).toLocaleDateString()}
                    </td>
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
                <button type="button" className="w-full bg-gray-200 text-gray-700 py-2 rounded-lg mt-2 hover:bg-gray-300 transition font-semibold" onClick={() => { setEditingProduct(null); setProductForm({ name: '', category: 'Vegetable', description: '', pricePerUnit: '', unit: '' }); }}>
                  Cancel Edit
                </button>
              )}
            </form>
          </div>
        )}

        {/* Add Inventory Form */}
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