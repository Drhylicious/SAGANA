import React from 'react';
import { useCart } from '../context/CartContext';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import API from '../api/axios';


const Checkout = () => {
  const { cart, clearCart } = useCart();
  const { user } = useAuth();
  const navigate = useNavigate();
  const cartTotal = cart.reduce((sum, item) => sum + item.pricePerUnit * item.qty, 0);

  const handlePlaceOrder = async () => {
    try {
      // Place each cart item as a separate order (adapt as needed for your backend)
      for (const item of cart) {
        await API.post('/orders', {
          product: item._id,
          inventoryBatch: item.inventoryBatch, // ensure this is available in cart item
          quantityOrdered: item.qty
        });
      }
      clearCart();
      navigate('/order-success');
    } catch (err) {
      alert('Failed to place order. Please try again.');
    }
  };

  return (
    <div className="max-w-2xl mx-auto p-6 bg-white rounded-xl shadow mt-8">
      <h1 className="text-2xl font-bold text-primary mb-4">Checkout</h1>
      <h2 className="text-lg font-semibold mb-2">Order Summary</h2>
      <ul className="mb-4">
        {cart.map(item => (
          <li key={item._id} className="flex justify-between items-center py-2 border-b last:border-b-0">
            <span>{item.name} x {item.qty}</span>
            <span>₱{(item.pricePerUnit * item.qty).toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
          </li>
        ))}
      </ul>
      <div className="flex justify-between font-bold text-lg mb-2">
        <span>Total:</span>
        <span>₱{cartTotal.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
      </div>
      <div className="text-xs text-gray-400 mb-4">12% VAT included</div>
      <div className="mb-6">
        <div className="text-gray-600 mb-2">Shipping and payment details coming soon.</div>
      </div>
      <button className="w-full py-3 bg-blue-600 text-white font-bold rounded-lg hover:bg-blue-700" onClick={handlePlaceOrder} disabled={cart.length === 0}>
        Place Order
      </button>
    </div>
  );
};

export default Checkout;
