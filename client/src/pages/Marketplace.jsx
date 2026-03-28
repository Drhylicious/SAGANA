import { useState, useEffect } from 'react';
import API from '../api/axios';
import ProductCard from '../components/ProductCard';

const Marketplace = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [category, setCategory] = useState('');

  const categories = ['All', 'Vegetable', 'Fruit', 'Grain', 'Spice', 'Other'];

  useEffect(() => {
    fetchProducts();
  }, [category]);

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const params = category && category !== 'All' ? `?category=${category}` : '';
      const { data } = await API.get(`/products${params}`);
      setProducts(data.data);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-6xl mx-auto px-4 py-8">
      {/* Hero */}
      <div className="bg-primary text-white rounded-2xl p-8 mb-8 text-center">
        <h1 className="text-4xl font-bold mb-2">🌾 SAGANA Marketplace</h1>
        <p className="text-lg opacity-90">
          Fresh produce directly from the cooperatives of Boac, Marinduque
        </p>
      </div>

      {/* Category Filter */}
      <div className="flex gap-2 flex-wrap mb-6">
        {categories.map((cat) => (
          <button
            key={cat}
            onClick={() => setCategory(cat === 'All' ? '' : cat)}
            className={`px-4 py-2 rounded-full text-sm font-semibold border transition
              ${(category === '' && cat === 'All') || category === cat
                ? 'bg-primary text-white border-primary'
                : 'bg-white text-gray-600 border-gray-300 hover:border-primary hover:text-primary'
              }`}
          >
            {cat}
          </button>
        ))}
      </div>

      {/* Products Grid */}
      {loading ? (
        <div className="text-center py-20 text-gray-400 text-lg">Loading products...</div>
      ) : products.length === 0 ? (
        <div className="text-center py-20 text-gray-400 text-lg">
          No products available yet.
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {products.map((product) => (
            <ProductCard key={product._id} product={product} />
          ))}
        </div>
      )}
    </div>
  );
};

export default Marketplace;