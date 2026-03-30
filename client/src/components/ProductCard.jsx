import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';

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
  const handleAddToCart = () => {
    if (!user) {
      navigate('/login');
    } else if (user.role === 'buyer') {
      addToCart(product);
      if (onAddedToCart) onAddedToCart();
    } else {
      navigate('/');
    }
  };

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-100 hover:shadow-md transition overflow-hidden">
      {/* Card Header */}
      <div className="bg-gradient-to-r from-primary to-secondary p-4">
        <div className="text-4xl text-center">🌿</div>
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
          className="w-full bg-primary text-white py-2 rounded-lg hover:bg-secondary transition font-semibold text-sm flex items-center justify-center gap-2"
        >
          <span className="text-lg">🛒</span>
          {user?.role === 'buyer' ? 'Add to Cart' : user ? 'View Marketplace' : 'Login to Order'}
        </button>
      </div>
    </div>
  );
};

export default ProductCard;