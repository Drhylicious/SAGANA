import { Link, useNavigate } from 'react-router-dom';
import { useState } from 'react';
import logo from '../assets/logo.png';
import { useAuth } from '../context/AuthContext';
import CartSidebar from './CartSidebar';

const Navbar = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [cartOpen, setCartOpen] = useState(false);

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  const getDashboardLink = () => {
    if (user?.role === 'admin') return '/admin';
    if (user?.role === 'farmer') return '/farmer';
    if (user?.role === 'buyer') return '/buyer';
  };

  const handleSearchSubmit = (e) => {
    e.preventDefault();
    if (search.trim()) {
      navigate(`/?search=${encodeURIComponent(search)}`);
    }
  };

  return (
    <nav className="bg-primary text-white px-6 py-3 shadow-md sticky top-0 z-50">
      <div className="flex justify-between items-center gap-4">
        {/* Logo */}
        <Link to="/" className="flex items-center gap-2 flex-shrink-0">
          <div className="w-8 h-8 flex items-center">
            <img src={logo} alt="SAGANA" className="w-full h-full object-contain brightness-0 invert" />
          </div>
          <span className="text-xl font-bold tracking-wide">SAGANA</span>
        </Link>

        {/* Search Bar */}
        <form onSubmit={handleSearchSubmit} className="flex-1 max-w-md">
          <div className="relative">
            <input
              type="text"
              placeholder="Search for r"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full px-4 py-2.5 rounded-full text-gray-700 text-sm focus:outline-none focus:ring-2 focus:ring-white"
            />
            <button
              type="submit"
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
            >
              🔍
            </button>
          </div>
        </form>

        {/* Right Section: Login/Register + Cart */}
        <div className="flex items-center gap-3 flex-shrink-0">
          {user ? (
            <>
              <Link
                to={getDashboardLink()}
                className="hidden sm:flex items-center gap-2 px-3 py-2 text-sm font-semibold hover:bg-white/10 rounded-full transition"
              >
                👤 {user.name}
              </Link>
              <button
                onClick={handleLogout}
                className="hidden sm:block px-3 py-2 text-sm font-semibold rounded-full border border-white hover:bg-white/10 transition"
              >
                Logout
              </button>
            </>
          ) : (
            <>
              <Link
                to="/login"
                className="px-3 py-2 text-sm font-semibold rounded-full border border-white hover:bg-white/10 transition whitespace-nowrap"
              >
                Login
              </Link>
              <Link
                to="/register"
                className="px-4 py-2 text-sm font-semibold rounded-full bg-white text-primary hover:bg-gray-100 transition whitespace-nowrap"
              >
                Register
              </Link>
            </>
          )}

          {/* Cart Icon */}
          <button
            onClick={() => setCartOpen(true)}
            className="text-2xl p-2 hover:bg-white/10 rounded-full transition"
            title="Cart"
          >
            🛒
          </button>
          <CartSidebar isOpen={cartOpen} onClose={() => setCartOpen(false)} />
        </div>
      </div>
    </nav>
  );
};

export default Navbar;
