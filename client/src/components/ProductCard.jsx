import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useEffect, useState } from 'react';
import API from '../api/axios';

const ProductCard = ({ product, onAddedToCart }) => {
  const { user } = useAuth();
  const navigate = useNavigate();

  const categoryColors = {
    Vegetable: 'bg-green-100 text-green-700',
    Fruit: 'bg-orange-100 text-orange-700',
    Grain: 'bg-yellow-100 text-yellow-700',
    Spice: 'bg-red-100 text-red-700',
    'Fresh Meat': 'bg-pink-100 text-pink-700',
    Seafood: 'bg-blue-100 text-blue-700',
    Other: 'bg-gray-100 text-gray-700',
  };


  const { addToCart } = useCart();
  const [batchId, setBatchId] = useState(null);
  const [batchLoading, setBatchLoading] = useState(false);
  const [batchError, setBatchError] = useState(null);

  useEffect(() => {
    const fetchBatch = async () => {
      setBatchLoading(true);
      setBatchError(null);
      try {
        const { data } = await API.get(`/inventory/available?product=${product._id}`);
        if (data.data && data.data.length > 0) {
          setBatchId(data.data[0]._id); // Use the first available batch
        } else {
          setBatchId(null);
        }
      } catch (err) {
        setBatchError('No available batch');
        setBatchId(null);
      } finally {
        setBatchLoading(false);
      }
    };
    fetchBatch();
  }, [product._id]);

  const handleAddToCart = () => {
    if (!user) {
      navigate('/login');
    } else if (user.role === 'buyer') {
      if (!batchId) {
        alert('No available stock for this product.');
        return;
      }
      addToCart(product, batchId);
      if (onAddedToCart) onAddedToCart();
    } else {
      navigate('/');
    }
  };

  // Compute image URL if present
  let imageUrl = null;
  if (product.image) {
    // If image path is relative, prepend API URL
    imageUrl = product.image.startsWith('http')
      ? product.image
      : `${import.meta.env.VITE_API_URL?.replace('/api/v1','') || 'http://localhost:5000'}${product.image}`;
  }

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-100 hover:shadow-md transition overflow-hidden">
      {/* Card Header with image or emoji */}
      <div className="bg-gradient-to-r from-primary to-secondary p-4 flex justify-center items-center h-28">
        {imageUrl ? (
          <img
            src={imageUrl}
            alt={product.name}
            className="h-20 w-20 object-cover rounded-full border-4 border-white shadow"
            style={{ background: '#f3f4f6' }}
          />
        ) : (
          <div className="text-4xl text-center">🌿</div>
        )}
      </div>

      {/* Card Body */}
      <div className="p-5">
        <div className="flex justify-between items-start mb-2">
          <h3 className="text-lg font-bold text-gray-800">{product.name}</h3>
          <span className={`text-xs px-2 py-1 rounded-full font-medium ${categoryColors[product.category]}`}>
            {product.category}
          </span>
        </div>

        {product.description && (
          <p className="text-gray-500 text-sm mb-3">{product.description}</p>
        )}

        <div className="flex justify-between items-center mb-3">
          <span className="text-2xl font-bold text-primary">
            ₱{product.pricePerUnit}
          </span>
          <span className="text-gray-400 text-sm">per {product.unit}</span>
        </div>

        <p className="text-xs text-gray-400 mb-4">
          🧑‍🌾 {product.farmer?.name || 'Local Farmer'}
        </p>

        <button
          onClick={handleAddToCart}
          className="w-full bg-primary text-white py-2 rounded-lg hover:bg-secondary transition font-semibold text-sm flex items-center justify-center gap-2 disabled:opacity-60"
          disabled={batchLoading || !batchId}
        >
          <span className="text-lg">🛒</span>
          {batchLoading
            ? 'Checking Stock...'
            : !batchId
              ? 'Out of Stock'
              : user?.role === 'buyer'
                ? 'Add to Cart'
                : user
                  ? 'View Marketplace'
                  : 'Login to Order'}
        </button>
      </div>
    </div>
  );
};

export default ProductCard;