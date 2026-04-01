import React, { useState } from 'react';
import { useCart } from '../context/CartContext';
import { useNavigate } from 'react-router-dom';

const CartSidebar = ({ isOpen, onClose }) => {
  const { cart, removeFromCart, increaseQty, decreaseQty } = useCart();
  const [wishlist, setWishlist] = useState([]);
  const navigate = useNavigate();
  if (!isOpen) return null;
  const cartTotal = cart.reduce((sum, item) => sum + item.pricePerUnit * item.qty, 0);

  // Wishlist toggle handler
  const toggleWishlist = (id) => {
    setWishlist((prev) =>
      prev.includes(id) ? prev.filter((wid) => wid !== id) : [...prev, id]
    );
  };

  const handleViewCart = () => {
    onClose();
    navigate('/cart');
  };

  const handleCheckout = () => {
    onClose();
    navigate('/checkout'); // You may need to implement this page/route
  };

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      {/* Overlay */}
      <div
        className="absolute inset-0 bg-black bg-opacity-30"
        onClick={onClose}
      />
      {/* Sidebar */}
      <div className="relative w-full max-w-sm h-full bg-white shadow-xl flex flex-col">
        <div className="flex items-center justify-between px-6 py-4 border-b">
          <h2 className="text-2xl font-bold text-primary">Your items</h2>
          <button onClick={onClose} className="text-2xl text-primary">&times;</button>
        </div>
        <div className="flex-1 flex flex-col p-4 overflow-y-auto">
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
                  <li key={item._id} className="flex items-center justify-between py-4">
                    <div className="flex items-center gap-3 w-2/3">
                      <img src={item.image || '/placeholder.png'} alt={item.name} className="w-14 h-14 object-cover rounded" />
                      <div className="flex flex-col">
                        <span className="font-semibold text-gray-800 text-sm">{item.name}</span>
                        <span className="text-xs text-gray-500">In Stock</span>
                        <span className="text-xs text-gray-700">₱{item.pricePerUnit.toLocaleString()}</span>
                      </div>
                    </div>
                    <div className="flex flex-col items-end gap-2">
                      <div className="flex items-center border rounded-lg overflow-hidden">
                        <button onClick={() => decreaseQty(item._id)} className="px-3 py-1 text-lg font-bold text-white bg-blue-600 hover:bg-blue-700 focus:outline-none">-</button>
                        <span className="w-8 py-1 text-center bg-white text-blue-700 font-semibold border-x border-gray-200">{item.qty}</span>
                        <button onClick={() => increaseQty(item._id)} className="px-3 py-1 text-lg font-bold text-white bg-blue-600 hover:bg-blue-700 focus:outline-none">+</button>
                      </div>
                      <div className="flex gap-2 mt-1">
                        <button
                          className={`text-xl ${wishlist.includes(item._id) ? 'text-pink-500' : 'text-blue-500'} hover:text-pink-600`}
                          title={wishlist.includes(item._id) ? 'Remove from wishlist' : 'Add to wishlist'}
                          onClick={() => toggleWishlist(item._id)}
                        >
                          <span role="img" aria-label="wishlist">{wishlist.includes(item._id) ? '❤️' : '♡'}</span>
                        </button>
                        <button onClick={() => removeFromCart(item._id)} className="text-red-500 hover:text-red-700 text-xl" title="Remove">
                          <span role="img" aria-label="remove">🗑️</span>
                        </button>
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
              <div className="mt-auto border-t pt-4">
                <div className="flex justify-between text-sm text-gray-600 mb-1">
                  <span>Subtotal</span>
                  <span className="font-bold text-blue-700 text-lg">₱{cartTotal.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                </div>
                <div className="text-xs text-gray-400 mb-2">12% VAT included</div>
                <div className="text-xs text-gray-400 mb-4">Vouchers and Final Total on Checkout</div>
                <div className="flex gap-2">
                  <button className="flex-1 py-2 border border-blue-600 text-blue-700 font-semibold rounded-lg hover:bg-blue-50" onClick={handleViewCart}>View cart</button>
                  <button className="flex-1 py-2 bg-blue-600 text-white font-semibold rounded-lg hover:bg-blue-700" onClick={handleCheckout}>Checkout</button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default CartSidebar;
