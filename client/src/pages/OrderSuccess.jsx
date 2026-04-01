import React from 'react';
import { Link } from 'react-router-dom';

const OrderSuccess = () => (
  <div className="max-w-md mx-auto p-8 mt-16 bg-white rounded-xl shadow text-center">
    <h1 className="text-3xl font-bold text-green-600 mb-4">Order Placed!</h1>
    <p className="mb-4">Thank you for your purchase. Your order has been placed successfully.</p>
    <Link to="/" className="inline-block mt-4 px-6 py-2 bg-blue-600 text-white font-semibold rounded-lg hover:bg-blue-700">Back to Home</Link>
  </div>
);

export default OrderSuccess;
