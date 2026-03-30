import React from 'react';
import { useCart } from '../context/CartContext';

const CartSidebar = ({ isOpen, onClose }) => {
  const { cart, removeFromCart } = useCart();
  if (!isOpen) return null;
  const cartTotal = cart.reduce((sum, item) => sum + item.pricePerUnit * item.qty, 0);
  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      {/* Overlay */}
      <div
        className="absolute inset-0 bg-black bg-opacity-30"
        onClick={onClose}
      />
      {/* Sidebar */}
      <div className="relative w-full max-w-xs h-full bg-gray-50 shadow-xl p-4 flex flex-col">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-2xl font-bold text-primary">Your items</h2>
          <button onClick={onClose} className="text-2xl text-primary">&times;</button>
        </div>
        <div className="flex-1 flex flex-col border rounded-lg bg-white p-2 overflow-y-auto">
          {cart.length === 0 ? (
            <div className="flex flex-col flex-1 justify-center items-center">
              <p className="text-gray-500 text-center mt-8">You haven't added any items yet.<br/>Get started by shopping your essentials and favorites!</p>
              <button
                className="mt-6 px-6 py-2 bg-blue-600 text-white font-semibold rounded-lg shadow hover:bg-blue-700 focus:outline-none"
                onClick={onClose}
              >
                Continue Shopping
              </button>
            </div>
          ) : (
            <>
              <ul className="flex-1 divide-y divide-gray-100 mb-4">
                {cart.map(item => (
                  <li key={item._id} className="flex items-center justify-between py-3">
                    <div>
                      <div className="font-semibold text-gray-800">{item.name}</div>
                      <div className="text-xs text-gray-500">Qty: {item.qty} &times; ₱{item.pricePerUnit}</div>
                    </div>
                    <button onClick={() => removeFromCart(item._id)} className="text-red-500 hover:text-red-700 text-lg ml-2">&times;</button>
                  </li>
                ))}
              </ul>
              <div className="mt-auto border-t pt-4">
                <div className="flex justify-between font-bold text-lg">
                  <span>Total:</span>
                  <span>₱{cartTotal.toLocaleString()}</span>
                </div>
                <button
                  className="w-full mt-4 px-6 py-2 bg-blue-600 text-white font-semibold rounded-lg shadow hover:bg-blue-700 focus:outline-none"
                  onClick={onClose}
                >
                  Continue Shopping
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default CartSidebar;
