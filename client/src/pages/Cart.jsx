import React from 'react';
import { useCart } from '../context/CartContext';
import { useNavigate } from 'react-router-dom';

const Cart = () => {
  const { cart, removeFromCart, increaseQty, decreaseQty } = useCart();
  const cartTotal = cart.reduce((sum, item) => sum + item.pricePerUnit * item.qty, 0);
  const navigate = useNavigate();

  return (
    <div className="flex flex-col md:flex-row gap-6 p-6">
      <div className="flex-1 bg-white rounded-xl shadow p-6">
        <h1 className="text-3xl font-bold text-primary mb-4">Cart</h1>
        <ul>
          {cart.map(item => (
            <li key={item._id} className="flex items-center justify-between py-6 border-b last:border-b-0">
              <div className="flex items-center gap-4">
                <img src={item.image || '/placeholder.png'} alt={item.name} className="w-20 h-20 object-cover rounded" />
                <div>
                  <div className="font-bold text-lg text-gray-800">{item.name}</div>
                  <div className="text-xs text-gray-500 mb-1">In Stock</div>
                  <div className="text-sm text-gray-700">₱{item.pricePerUnit.toLocaleString()}</div>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <button onClick={() => decreaseQty(item._id)} className="px-3 py-1 bg-blue-100 text-blue-700 font-bold rounded hover:bg-blue-200">-</button>
                <span className="w-8 text-center">{item.qty}</span>
                <button onClick={() => increaseQty(item._id)} className="px-3 py-1 bg-blue-100 text-blue-700 font-bold rounded hover:bg-blue-200">+</button>
                <button onClick={() => removeFromCart(item._id)} className="ml-3 text-red-500 hover:text-red-700 text-xl" title="Remove">
                  <span role="img" aria-label="remove">🗑️</span>
                </button>
              </div>
            </li>
          ))}
        </ul>
      </div>
      <div className="w-full md:w-96 bg-white rounded-xl shadow p-6 h-fit">
        <h2 className="text-xl font-bold text-blue-700 mb-2">Order details</h2>
        <div className="flex justify-between mb-2">
          <span>Item total</span>
          <span className="font-semibold">₱{cartTotal.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
        </div>
        <div className="mb-2">
          <span className="font-bold text-blue-700">Subtotal</span>
          <span className="float-right font-bold text-blue-700">₱{cartTotal.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
        </div>
        <div className="text-xs text-gray-400 mb-2">12% VAT included</div>
        <div className="text-xs text-gray-400 mb-4">Vouchers and Final Total on Checkout</div>
        <button
          className="w-full py-3 bg-blue-600 text-white font-bold rounded-lg hover:bg-blue-700"
          onClick={() => navigate('/checkout')}
          disabled={cart.length === 0}
        >
          Checkout
        </button>
      </div>
    </div>
  );
};

export default Cart;
