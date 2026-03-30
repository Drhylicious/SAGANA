import { useState, useEffect } from 'react';
import API from '../api/axios';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import PageWrapper from '../components/PageWrapper';

const AdminDashboard = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [products, setProducts] = useState([]);
  const [orders, setOrders] = useState([]);
  const [users, setUsers] = useState([]);
  const [activeTab, setActiveTab] = useState('home');
  const [loading, setLoading] = useState(true);

  useEffect(() => { fetchData(); }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const [productsRes, ordersRes, usersRes] = await Promise.all([
        API.get('/products/all'),
        API.get('/orders'),
        API.get('/auth/users')
      ]);
      setProducts(productsRes.data.data);
      setOrders(ordersRes.data.data);
      setUsers(usersRes.data.data);
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

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  const statusColors = {
    Pending: 'bg-yellow-100 text-yellow-700',
    Confirmed: 'bg-blue-100 text-blue-700',
    Completed: 'bg-green-100 text-green-700',
    Cancelled: 'bg-red-100 text-red-700',
  };

  const navItems = [
    { key: 'home', label: 'Home', icon: '🏠' },
    { key: 'products', label: 'Products', icon: '📦' },
    { key: 'orders', label: 'Orders', icon: '🧾' },
    { key: 'users', label: 'Users', icon: '👥' },
    { key: 'marketplace', label: 'Marketplace', icon: '🛒' },
  ];

  const pendingProducts = products.filter(p => !p.isApproved).length;
  const pendingOrders = orders.filter(o => o.status === 'Pending').length;

  if (loading) return (
    <div className="flex h-screen items-center justify-center text-gray-400 text-lg">
      Loading...
    </div>
  );

  return (
    <PageWrapper>
      <div className="flex h-screen overflow-hidden">

        {/* ── SIDEBAR ── */}
        <div className="w-56 flex-shrink-0 bg-gradient-to-b from-primary to-secondary flex flex-col text-white">
          {/* Admin Info */}
          <div className="flex flex-col items-center py-8 px-4 border-b border-white/20">
            <div className="w-16 h-16 rounded-full bg-white/20 flex items-center justify-center text-3xl mb-2">
              👤
            </div>
            <p className="font-semibold text-sm text-center">{user?.name}</p>
            <p className="text-xs text-white/60">Administrator</p>
          </div>

          {/* Nav Links */}
          <nav className="flex flex-col gap-1 p-4 flex-1">
            {navItems.map((item) => (
              <button
                key={item.key}
                onClick={() => {
                  if (item.key === 'marketplace') {
                    navigate('/');
                  } else {
                    setActiveTab(item.key);
                  }
                }}
                className={`flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium transition text-left w-full ${
                  activeTab === item.key
                    ? 'bg-white/20 text-white'
                    : 'text-white/70 hover:bg-white/10 hover:text-white'
                }`}
              >
                <span className="text-lg">{item.icon}</span>
                {item.label}
              </button>
            ))}
          </nav>

          {/* Logout */}
          <div className="p-4 border-t border-white/20">
            <button
              onClick={handleLogout}
              className="w-full flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium text-white/70 hover:bg-white/10 hover:text-white transition"
            >
              <span className="text-lg">🚪</span>
              Logout
            </button>
          </div>
        </div>

        {/* ── MAIN CONTENT ── */}
        <div className="flex-1 overflow-y-auto bg-gray-50">
          <div className="p-8">

            {/* Header */}
            <div className="mb-8">
              <h1 className="text-2xl font-bold text-gray-800">
                Welcome back, {user?.name}! 👋
              </h1>
              <p className="text-gray-400 text-sm mt-1">
                {new Date().toLocaleDateString('en-PH', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
              </p>
            </div>

            {/* ── HOME TAB ── */}
            {activeTab === 'home' && (
              <div>
                {/* Stat Cards */}
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5 mb-8">
                  {[
                    { label: 'Total Products', value: products.length, icon: '📦', color: 'from-green-400 to-green-600' },
                    { label: 'Pending Approval', value: pendingProducts, icon: '⏳', color: 'from-yellow-400 to-yellow-600' },
                    { label: 'Total Orders', value: orders.length, icon: '🧾', color: 'from-blue-400 to-blue-600' },
                    { label: 'Pending Orders', value: pendingOrders, icon: '🕐', color: 'from-orange-400 to-orange-600' },
                  ].map((stat) => (
                    <div key={stat.label}
                      className={`bg-gradient-to-br ${stat.color} text-white rounded-2xl p-6 flex items-center justify-between shadow-sm`}
                    >
                      <div>
                        <p className="text-white/80 text-sm">{stat.label}</p>
                        <p className="text-4xl font-bold mt-1">{stat.value}</p>
                      </div>
                      <span className="text-4xl opacity-80">{stat.icon}</span>
                    </div>
                  ))}
                </div>

                {/* Recent Orders */}
                <div className="bg-white rounded-2xl shadow-sm border p-6">
                  <h2 className="text-lg font-bold text-gray-800 mb-4">Recent Orders</h2>
                  <table className="w-full text-sm">
                    <thead className="bg-gray-50 text-gray-500">
                      <tr>
                        <th className="text-left px-4 py-3 rounded-l-lg">Buyer</th>
                        <th className="text-left px-4 py-3">Product</th>
                        <th className="text-left px-4 py-3">Total</th>
                        <th className="text-left px-4 py-3 rounded-r-lg">Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {orders.slice(0, 5).map((order) => (
                        <tr key={order._id} className="border-t hover:bg-gray-50">
                          <td className="px-4 py-3">{order.buyer?.name}</td>
                          <td className="px-4 py-3 font-medium">{order.product?.name || '—'}</td>
                          <td className="px-4 py-3 font-semibold text-primary">₱{order.totalPrice}</td>
                          <td className="px-4 py-3">
                            <span className={`px-2 py-1 rounded-full text-xs font-medium ${statusColors[order.status]}`}>
                              {order.status}
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {/* ── PRODUCTS TAB ── */}
            {activeTab === 'products' && (
              <div className="bg-white rounded-2xl shadow-sm border overflow-hidden">
                <div className="p-6 border-b">
                  <h2 className="text-lg font-bold text-gray-800">All Products</h2>
                  <p className="text-gray-400 text-sm">{pendingProducts} pending approval</p>
                </div>
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 text-gray-500">
                    <tr>
                      <th className="text-left px-6 py-3">Product</th>
                      <th className="text-left px-6 py-3">Farmer</th>
                      <th className="text-left px-6 py-3">Price</th>
                      <th className="text-left px-6 py-3">Status</th>
                      <th className="text-left px-6 py-3">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {products.map((product) => (
                      <tr key={product._id} className="border-t hover:bg-gray-50">
                        <td className="px-6 py-4 font-medium">{product.name}</td>
                        <td className="px-6 py-4 text-gray-500">{product.farmer?.name}</td>
                        <td className="px-6 py-4">₱{product.pricePerUnit}/{product.unit}</td>
                        <td className="px-6 py-4">
                          <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                            product.isApproved ? 'bg-green-100 text-green-700' : 'bg-yellow-100 text-yellow-700'
                          }`}>
                            {product.isApproved ? 'Approved' : 'Pending'}
                          </span>
                        </td>
                        <td className="px-6 py-4 flex gap-2">
                          {!product.isApproved && (
                            <button
                              onClick={() => handleApprove(product._id)}
                              className="bg-primary text-white px-3 py-1 rounded-lg text-xs hover:bg-secondary transition"
                            >
                              Approve
                            </button>
                          )}
                          <button
                            onClick={() => handleDelete(product._id)}
                            className="bg-red-500 text-white px-3 py-1 rounded-lg text-xs hover:bg-red-600 transition"
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

            {/* ── ORDERS TAB ── */}
            {activeTab === 'orders' && (
              <div className="bg-white rounded-2xl shadow-sm border overflow-hidden">
                <div className="p-6 border-b">
                  <h2 className="text-lg font-bold text-gray-800">All Orders</h2>
                  <p className="text-gray-400 text-sm">{pendingOrders} pending orders</p>
                </div>
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 text-gray-500">
                    <tr>
                      <th className="text-left px-6 py-3">Buyer</th>
                      <th className="text-left px-6 py-3">Product</th>
                      <th className="text-left px-6 py-3">Qty</th>
                      <th className="text-left px-6 py-3">Total</th>
                      <th className="text-left px-6 py-3">Status</th>
                      <th className="text-left px-6 py-3">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {orders.map((order) => (
                      <tr key={order._id} className="border-t hover:bg-gray-50">
                        <td className="px-6 py-4">{order.buyer?.name}</td>
                        <td className="px-6 py-4 font-medium">{order.product?.name || '—'}</td>
                        <td className="px-6 py-4">{order.quantityOrdered} {order.product?.unit}</td>
                        <td className="px-6 py-4 font-semibold text-primary">₱{order.totalPrice}</td>
                        <td className="px-6 py-4">
                          <span className={`px-2 py-1 rounded-full text-xs font-medium ${statusColors[order.status]}`}>
                            {order.status}
                          </span>
                        </td>
                        <td className="px-6 py-4">
                          <select
                            value={order.status}
                            onChange={(e) => handleOrderStatus(order._id, e.target.value)}
                            className="border rounded-lg px-2 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-primary"
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

            {/* ── USERS TAB ── */}
            {activeTab === 'users' && (
              <div className="bg-white rounded-2xl shadow-sm border overflow-hidden">
                <div className="p-6 border-b">
                  <h2 className="text-lg font-bold text-gray-800">All Users</h2>
                  <p className="text-gray-400 text-sm">{users.length} registered accounts</p>
                </div>
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 text-gray-500">
                    <tr>
                      <th className="text-left px-6 py-3">Name</th>
                      <th className="text-left px-6 py-3">Email</th>
                      <th className="text-left px-6 py-3">Role</th>
                      <th className="text-left px-6 py-3">Joined</th>
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((u) => (
                      <tr key={u._id} className="border-t hover:bg-gray-50">
                        <td className="px-6 py-4 font-medium">{u.name}</td>
                        <td className="px-6 py-4 text-gray-500">{u.email}</td>
                        <td className="px-6 py-4">
                          <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                            u.role === 'admin' ? 'bg-purple-100 text-purple-700'
                            : u.role === 'farmer' ? 'bg-green-100 text-green-700'
                            : 'bg-blue-100 text-blue-700'
                          }`}>
                            {u.role.toUpperCase()}
                          </span>
                        </td>
                        <td className="px-6 py-4 text-gray-400">
                          {new Date(u.createdAt).toLocaleDateString()}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

          </div>
        </div>
      </div>
    </PageWrapper>
  );
};

export default AdminDashboard;