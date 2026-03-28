import { useState, useEffect } from 'react';
import API from '../api/axios';

const AdminDashboard = () => {
  const [products, setProducts] = useState([]);
  const [orders, setOrders] = useState([]);
  const [activeTab, setActiveTab] = useState('products');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const [allProductsRes, ordersRes] = await Promise.all([
        API.get('/products/all?limit=100'),
        API.get('/orders')
      ]);
      setProducts(allProductsRes.data.data);
      setOrders(ordersRes.data.data);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  const handleApprove = async (id) => {
    try {
      await API.put(`/products/${id}/approve`);
      fetchData();
    } catch (error) {
      console.error(error);
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Are you sure you want to delete this product?')) return;
    try {
      await API.delete(`/products/${id}`);
      fetchData();
    } catch (error) {
      console.error(error);
    }
  };

  const handleOrderStatus = async (id, status) => {
    try {
      await API.put(`/orders/${id}/status`, { status });
      fetchData();
    } catch (error) {
      console.error(error);
    }
  };

  const statusColors = {
    Pending: 'bg-yellow-100 text-yellow-700',
    Confirmed: 'bg-blue-100 text-blue-700',
    Completed: 'bg-green-100 text-green-700',
    Cancelled: 'bg-red-100 text-red-700',
  };

  if (loading) return <div className="text-center py-20 text-gray-400">Loading...</div>;

  return (
    <div className="max-w-6xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-primary mb-2">Admin Dashboard</h1>
      <p className="text-gray-500 mb-6">Manage products and orders for SAGANA</p>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        <div className="bg-white rounded-xl p-5 shadow-sm border text-center">
          <p className="text-3xl font-bold text-primary">{products.length}</p>
          <p className="text-gray-500 text-sm mt-1">Total Products</p>
        </div>
        <div className="bg-white rounded-xl p-5 shadow-sm border text-center">
          <p className="text-3xl font-bold text-yellow-500">
            {products.filter(p => !p.isApproved).length}
          </p>
          <p className="text-gray-500 text-sm mt-1">Pending Approval</p>
        </div>
        <div className="bg-white rounded-xl p-5 shadow-sm border text-center">
          <p className="text-3xl font-bold text-blue-500">{orders.length}</p>
          <p className="text-gray-500 text-sm mt-1">Total Orders</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 mb-6">
        <button
          onClick={() => setActiveTab('products')}
          className={`px-5 py-2 rounded-lg font-semibold transition ${
            activeTab === 'products'
              ? 'bg-primary text-white'
              : 'bg-white text-gray-600 border hover:border-primary'
          }`}
        >
          Products
        </button>
        <button
          onClick={() => setActiveTab('orders')}
          className={`px-5 py-2 rounded-lg font-semibold transition ${
            activeTab === 'orders'
              ? 'bg-primary text-white'
              : 'bg-white text-gray-600 border hover:border-primary'
          }`}
        >
          Orders
        </button>
      </div>

      {/* Products Tab */}
      {activeTab === 'products' && (
        <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-600">
              <tr>
                <th className="text-left px-4 py-3">Product</th>
                <th className="text-left px-4 py-3">Farmer</th>
                <th className="text-left px-4 py-3">Price</th>
                <th className="text-left px-4 py-3">Status</th>
                <th className="text-left px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              {products.map((product) => (
                <tr key={product._id} className="border-t hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium">{product.name}</td>
                  <td className="px-4 py-3 text-gray-500">{product.farmer?.name}</td>
                  <td className="px-4 py-3">₱{product.pricePerUnit}/{product.unit}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                      product.isApproved
                        ? 'bg-green-100 text-green-700'
                        : 'bg-yellow-100 text-yellow-700'
                    }`}>
                      {product.isApproved ? 'Approved' : 'Pending'}
                    </span>
                  </td>
                  <td className="px-4 py-3 flex gap-2">
                    {!product.isApproved && (
                      <button
                        onClick={() => handleApprove(product._id)}
                        className="bg-primary text-white px-3 py-1 rounded text-xs hover:bg-secondary"
                      >
                        Approve
                      </button>
                    )}
                    <button
                      onClick={() => handleDelete(product._id)}
                      className="bg-red-500 text-white px-3 py-1 rounded text-xs hover:bg-red-600"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Orders Tab */}
      {activeTab === 'orders' && (
        <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-600">
              <tr>
                <th className="text-left px-4 py-3">Buyer</th>
                <th className="text-left px-4 py-3">Product</th>
                <th className="text-left px-4 py-3">Qty</th>
                <th className="text-left px-4 py-3">Total</th>
                <th className="text-left px-4 py-3">Status</th>
                <th className="text-left px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => (
                <tr key={order._id} className="border-t hover:bg-gray-50">
                  <td className="px-4 py-3">{order.buyer?.name}</td>
                  <td className="px-4 py-3 font-medium">{order.product?.name}</td>
                  <td className="px-4 py-3">{order.quantityOrdered} {order.product?.unit}</td>
                  <td className="px-4 py-3 font-semibold text-primary">₱{order.totalPrice}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${statusColors[order.status]}`}>
                      {order.status}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <select
                      value={order.status}
                      onChange={(e) => handleOrderStatus(order._id, e.target.value)}
                      className="border rounded px-2 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-primary"
                    >
                      <option value="Pending">Pending</option>
                      <option value="Confirmed">Confirmed</option>
                      <option value="Completed">Completed</option>
                      <option value="Cancelled">Cancelled</option>
                    </select>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

export default AdminDashboard;