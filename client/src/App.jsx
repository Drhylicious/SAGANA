import { useState } from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { AnimatePresence } from 'framer-motion';
import { useAuth } from './context/AuthContext';
import SplashScreen from './components/SplashScreen';
import Navbar from './components/Navbar';
import ProtectedRoute from './components/ProtectedRoute';
import Login from './pages/Login';
import Register from './pages/Register';
import Marketplace from './pages/Marketplace';
import AdminDashboard from './pages/AdminDashboard';
import FarmerDashboard from './pages/FarmerDashboard';
import BuyerDashboard from './pages/BuyerDashboard';

function App() {
  const { user } = useAuth();
  const [showSplash, setShowSplash] = useState(true);
  const location = useLocation();

  const hideNavbar = location.pathname === '/admin';

  if (showSplash) {
    return <SplashScreen onComplete={() => setShowSplash(false)} />;
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {!hideNavbar && <Navbar />}
      <AnimatePresence mode="wait">
        <Routes>
          <Route path="/" element={<Marketplace />} />
          <Route path="/login" element={!user ? <Login /> : <Navigate to="/" />} />
          <Route path="/register" element={!user ? <Register /> : <Navigate to="/" />} />
          <Route path="/admin" element={
            <ProtectedRoute role="admin"><AdminDashboard /></ProtectedRoute>
          } />
          <Route path="/farmer" element={
            <ProtectedRoute role="farmer"><FarmerDashboard /></ProtectedRoute>
          } />
          <Route path="/buyer" element={
            <ProtectedRoute role="buyer"><BuyerDashboard /></ProtectedRoute>
          } />
        </Routes>
      </AnimatePresence>
    </div>
  );
}

export default App;