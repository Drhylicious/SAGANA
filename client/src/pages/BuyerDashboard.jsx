import { useState, useEffect } from 'react';
import API from '../api/axios';
import { useAuth } from '../context/AuthContext';
import PageWrapper from '../components/PageWrapper';

const BuyerDashboard = () => {
  const { user } = useAuth();
  const [orders, setOrders] = useState([]);
  const [products, setProducts] = useState([]);
  const [inventory, setInventory] = useState([]);
  const [activeTab, setActiveTab] = useState('orders');
  const [loading, setLoading] = useState(true);
  const [orderForm, setOrderForm] = useState({ product: '', inventoryBatch: '', quantityOrdered: '' });

  const [message, setMessage] = useState('');
  // Edit/Delete Order Modal State
  const [showEditModal, setShowEditModal] = useState(false);
  const [editOrderId, setEditOrderId] = useState(null);
  const [editQuantity, setEditQuantity] = useState(1);
  // --- Edit/Delete Order Logic ---
  const openEditModal = (order) => {
    setEditOrderId(order._id);
    setEditQuantity(order.quantityOrdered);
    setShowEditModal(true);
  };
  const closeEditModal = () => {
    setShowEditModal(false);
    setEditOrderId(null);
  };

  const handleEditOrder = async (e) => {
    e.preventDefault();
    try {
      await API.put(`/orders/${editOrderId}`, { quantityOrdered: Number(editQuantity) });
      setMessage('✅ Order updated successfully!');
      closeEditModal();
      fetchData();
    } catch (error) {
      setMessage('❌ ' + (error.response?.data?.message || 'Error updating order'));
    }
  };

  const handleDeleteOrder = async (orderId) => {
    if (!window.confirm('Are you sure you want to delete this order?')) return;
    try {
      await API.delete(`/orders/${orderId}`);
      setMessage('✅ Order deleted successfully!');
      fetchData();
    } catch (error) {
      setMessage('❌ ' + (error.response?.data?.message || 'Error deleting order'));
    }
  };

  useEffect(() => { fetchData(); }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const [ordersRes, productsRes] = await Promise.all([
        API.get('/orders'),
        API.get('/products')
      ]);
      setOrders(ordersRes.data.data);
      setProducts(productsRes.data.data);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  const fetchInventoryForProduct = async (productId) => {
    try {
      // Use the new endpoint for buyers
      const { data } = await API.get(`/inventory/available?product=${productId}`);
      setInventory(data.data);
    } catch (error) {
      console.error(error);
    }
  };

  const handleProductChange = (e) => {
    const productId = e.target.value;
    setOrderForm({ ...orderForm, product: productId, inventoryBatch: '' });
    if (productId) fetchInventoryForProduct(productId);
  };

  const handlePlaceOrder = async (e) => {
    e.preventDefault();
    try {
      await API.post('/orders', orderForm);
      setMessage('✅ Order placed successfully!');
      setOrderForm({ product: '', inventoryBatch: '', quantityOrdered: '' });
      setInventory([]);
      fetchData();
    } catch (error) {
      setMessage('❌ ' + (error.response?.data?.message || 'Error placing order'));
    }
  };

  const statusColors = {
    Pending: 'bg-yellow-100 text-yellow-700',
    Confirmed: 'bg-blue-100 text-blue-700',
    Completed: 'bg-green-100 text-green-700',
    Cancelled: 'bg-red-100 text-red-700',
  };


  if (loading) return <div className="text-center py-20 text-gray-400">Loading...</div>;

  // Quick stats
  const totalOrders = orders.length;
  const confirmedOrders = orders.filter(o => o.status === 'Confirmed').length;
  const completedOrders = orders.filter(o => o.status === 'Completed').length;
  const totalSpent = orders.reduce((sum, o) => sum + (o.totalPrice || 0), 0);

  // Tab icons
  const tabIcons = {
    orders: '📦',
    'place-order': '🛒',
  };

  // Product icon by category
  const getProductIcon = (category) => {
    return category === 'Vegetable' ? '🥦'
      : category === 'Fruit' ? '🍎'
      : category === 'Grain' ? '🌾'
      : category === 'Spice' ? '🌶️'
      : category === 'Fresh Meat' ? '🥩'
      : category === 'Seafood' ? '🐟'
      : '📦';
  };

  return (
    <PageWrapper>
      <div className="max-w-6xl mx-auto px-4 py-8">
        <h1 className="text-3xl font-bold text-primary mb-2 flex items-center gap-2">
          Buyer Dashboard <span className="text-2xl">🛒</span>
        </h1>
        <p className="text-gray-500 mb-6">Welcome, {user?.name}! 🛒</p>

        {/* Quick Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">📦</span>
            <div className="text-lg font-bold">{totalOrders}</div>
            <div className="text-xs text-gray-500">Total Orders</div>
          </div>
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">✅</span>
            <div className="text-lg font-bold">{confirmedOrders}</div>
            <div className="text-xs text-gray-500">Confirmed</div>
          </div>
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">🎉</span>
            <div className="text-lg font-bold">{completedOrders}</div>
            <div className="text-xs text-gray-500">Completed</div>
          </div>
          <div className="bg-white rounded-xl shadow border p-4 flex flex-col items-center">
            <span className="text-3xl mb-1">💸</span>
            <div className="text-lg font-bold">₱{totalSpent.toLocaleString()}</div>
            <div className="text-xs text-gray-500">Total Spent</div>
          </div>
        </div>

        {message && (
          <div className="mb-4 px-4 py-3 rounded-lg bg-gray-100 text-sm">{message}</div>
        )}

        {/* Tabs */}
        <div className="flex gap-2 mb-6">
          {['orders', 'place-order'].map((tab) => (
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
              {tab === 'place-order' ? 'Place Order' : 'My Orders'}
            </button>
          ))}
        </div>

        {/* My Orders */}
        {activeTab === 'orders' && (
          <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
            {orders.length === 0 ? (
              <div className="text-center py-16 text-gray-400">
                No orders yet. Place your first order!
              </div>
            ) : (
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-gray-600">
                  <tr>
                    <th className="text-left px-4 py-3">Icon</th>
                    <th className="text-left px-4 py-3">Product</th>
                    <th className="text-left px-4 py-3">Quantity</th>
                    <th className="text-left px-4 py-3">Total</th>
                    <th className="text-left px-4 py-3">Date</th>
                    <th className="text-left px-4 py-3">Status</th>
                    <th className="text-left px-4 py-3">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {orders.map((order) => (
                    <tr key={order._id} className="border-t hover:bg-gray-50">
                      <td className="px-4 py-3 text-2xl">{getProductIcon(order.product?.category)}</td>
                      <td className="px-4 py-3 font-medium">{order.product?.name}</td>
                      <td className="px-4 py-3">{order.quantityOrdered} {order.product?.unit}</td>
                      <td className="px-4 py-3 font-semibold text-primary">₱{order.totalPrice}</td>
                      <td className="px-4 py-3 text-gray-500">
                        {new Date(order.createdAt).toLocaleDateString()}
                      </td>
                      <td className="px-4 py-3">
                        <span className={`px-2 py-1 rounded-full text-xs font-medium ${statusColors[order.status]}`}>
                          {order.status}
                        </span>
                      </td>
                      <td className="px-4 py-3 flex gap-2">
                        <button
                          className="bg-blue-500 text-white px-2 py-1 rounded text-xs hover:bg-blue-600 transition"
                          onClick={() => openEditModal(order)}
                        >Edit</button>
                        <button
                          className="bg-red-500 text-white px-2 py-1 rounded text-xs hover:bg-red-600 transition"
                          onClick={() => handleDeleteOrder(order._id)}
                        >Delete</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}

        {/* Edit Order Modal */}
        {showEditModal && (
          <div className="fixed inset-0 bg-black bg-opacity-30 flex items-center justify-center z-50">
            <div className="bg-white rounded-lg p-6 w-full max-w-xs shadow-lg">
              <h2 className="text-lg font-bold mb-2">Edit Order Quantity</h2>
              <form onSubmit={handleEditOrder} className="space-y-3">
                <input
                  type="number"
                  min={1}
                  value={editQuantity}
                  onChange={e => setEditQuantity(e.target.value)}
                  className="w-full border rounded px-3 py-2"
                  required
                />
                <div className="flex gap-2 justify-end">
                  <button type="button" onClick={closeEditModal} className="px-3 py-1 rounded bg-gray-200">Cancel</button>
                  <button type="submit" className="px-3 py-1 rounded bg-primary text-white">Save</button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* Place Order Form */}
        {activeTab === 'place-order' && (
          <div className="bg-white rounded-xl shadow-sm border p-6 max-w-lg">
            <h2 className="text-xl font-bold text-gray-800 mb-4">Place an Order</h2>
            <form onSubmit={handlePlaceOrder} className="space-y-4">
              <select required
                value={orderForm.product}
                onChange={handleProductChange}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              >
                <option value="">Select Product</option>
                {products.map(p => (
                  <option key={p._id} value={p._id}>{p.name} — ₱{p.pricePerUnit}/{p.unit}</option>
                ))}
              </select>
              <select required
                value={orderForm.inventoryBatch}
                onChange={(e) => setOrderForm({ ...orderForm, inventoryBatch: e.target.value })}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
                disabled={!orderForm.product}
              >
                <option value="">Select Batch</option>
                {inventory.map(b => (
                  <option key={b._id} value={b._id}>
                    {b.batchCode} — {b.quantity} available (expires {new Date(b.expiryDate).toLocaleDateString()})
                  </option>
                ))}
              </select>
              <input type="number" placeholder="Quantity" required min={1}
                value={orderForm.quantityOrdered}
                onChange={(e) => setOrderForm({ ...orderForm, quantityOrdered: e.target.value })}
                className="w-full border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              />
              <button type="submit"
                className="w-full bg-primary text-white py-2 rounded-lg hover:bg-secondary transition font-semibold"
              >
                Place Order
              </button>
            </form>
          </div>
        )}
      </div>
    </PageWrapper>
  );
}

export default BuyerDashboard;