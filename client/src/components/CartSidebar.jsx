import React from 'react';

const CartSidebar = ({ isOpen, onClose }) => {
  if (!isOpen) return null;
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
        <div className="flex-1 flex flex-col justify-center items-center border rounded-lg bg-white">
          <p className="text-gray-500 text-center mt-8">You haven't added any items yet.<br/>Get started by shopping your essentials and favorites!</p>
          <button
            className="mt-6 px-6 py-2 bg-blue-600 text-white font-semibold rounded-lg shadow hover:bg-blue-700 focus:outline-none"
            onClick={onClose}
          >
            Continue Shopping
          </button>
        </div>
      </div>
    </div>
  );
};

export default CartSidebar;
