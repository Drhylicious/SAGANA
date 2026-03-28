import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

const Navbar = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  const getDashboardLink = () => {
    if (user?.role === 'admin') return '/admin';
    if (user?.role === 'farmer') return '/farmer';
    if (user?.role === 'buyer') return '/buyer';
  };

  return (
    <nav className="bg-primary text-white px-6 py-4 flex justify-between items-center shadow-md">
      <Link to="/" className="text-2xl font-bold tracking-wide">
        🌿 SAGANA
      </Link>
      <div className="flex items-center gap-4">
        <Link to="/" className="hover:underline">Marketplace</Link>
        {user ? (
          <>
            <Link to={getDashboardLink()} className="hover:underline">
              Dashboard
            </Link>
            <span className="text-sm bg-white text-primary px-2 py-1 rounded-full font-semibold">
              {user.role.toUpperCase()}
            </span>
            <span className="text-sm">Hi, {user.name}!</span>
            <button
              onClick={handleLogout}
              className="bg-white text-primary px-3 py-1 rounded hover:bg-gray-100 font-semibold"
            >
              Logout
            </button>
          </>
        ) : (
          <>
            <Link to="/login" className="hover:underline">Login</Link>
            <Link
              to="/register"
              className="bg-white text-primary px-3 py-1 rounded hover:bg-gray-100 font-semibold"
            >
              Register
            </Link>
          </>
        )}
      </div>
    </nav>
  );
};

export default Navbar;