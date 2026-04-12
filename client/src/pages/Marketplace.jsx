import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import API from '../api/axios';
import { useAuth } from '../context/AuthContext';
import PageWrapper from '../components/PageWrapper';
import ProductCard from '../components/ProductCard';

const categoryIcons = {
  All: '🌾',
  Vegetable: '🥦',
  Fruit: '🍎',
  Grain: '🌾',
  Spice: '🌶️',
  'Fresh Meat': '🥩',
  Seafood: '🐟',
  Other: '📦',
};

const Marketplace = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [priceDropProducts, setPriceDropProducts] = useState([]);
  const [loadingPriceDrops, setLoadingPriceDrops] = useState(true);
  const [category, setCategory] = useState('All');
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [carouselIndex, setCarouselIndex] = useState(0);
  // Removed local cart state; use CartContext in ProductCard

  const categories = ['All', 'Vegetable', 'Fruit', 'Grain', 'Spice', 'Fresh Meat', 'Seafood'];

  const carouselSlides = [
    {
      title: 'Fresh from Local Farmers',
      subtitle: 'Quality produce from Torrijos, Marinduque every day',
      className: 'from-green-700 to-green-500',
    },
    {
      title: 'SAGANA Daily Deals',
      subtitle: 'Save on seasonal favorites and pantry staples',
      className: 'from-emerald-700 to-lime-500',
    },
    {
      title: 'Handpicked Quality',
      subtitle: 'Premium fresh meat, seafood, and vegetables',
      className: 'from-emerald-900 to-green-600',
    },
  ];

  useEffect(() => {
    fetchProducts();
  }, [category]);

  useEffect(() => {
    const fetchPriceDrops = async () => {
      try {
        setLoadingPriceDrops(true);
        const { data } = await API.get('/products/price-drops');
        setPriceDropProducts(data.data || []);
      } catch (error) {
        setPriceDropProducts([]);
      } finally {
        setLoadingPriceDrops(false);
      }
    };
    fetchPriceDrops();
  }, []);

  useEffect(() => {
    setSearch(searchParams.get('search') || '');
  }, [searchParams]);

  useEffect(() => {
    const timer = setInterval(() => {
      setCarouselIndex((prev) => (prev + 1) % carouselSlides.length);
    }, 4500);
    return () => clearInterval(timer);
  }, [carouselSlides.length]);

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const params = category !== 'All' ? `?category=${encodeURIComponent(category)}` : '';
      const { data } = await API.get(`/products${params}`);
      setProducts(data.data);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  const filteredProducts = products.filter(p =>
    p.name.toLowerCase().includes(search.toLowerCase()) ||
    p.description?.toLowerCase().includes(search.toLowerCase())
  );

  const featuredProducts = filteredProducts.slice(0, 6);
  // Show actual price drop products from backend
  const dealsProducts = priceDropProducts.slice(0, 6);

  const isCategoryView = category !== 'All';
  const categoryListings = isCategoryView ? filteredProducts : [];

  // Removed addToCart, removeFromCart, cartTotal (handled by context)

  const categoryColors = {
    Vegetable: 'bg-green-100 text-green-700',
    Fruit: 'bg-orange-100 text-orange-700',
    Grain: 'bg-yellow-100 text-yellow-700',
    Spice: 'bg-red-100 text-red-700',
    'Fresh Meat': 'bg-pink-100 text-pink-700',
    Seafood: 'bg-blue-100 text-blue-700',
    Other: 'bg-gray-100 text-gray-700',
  };

  return (
    <PageWrapper>
      <div className="min-h-screen bg-gray-50">
        <div className="flex max-w-7xl mx-auto px-4 py-6 gap-6">

          <aside className="hidden lg:block w-60">
            <div className="bg-white rounded-2xl shadow-sm border overflow-hidden sticky top-24">
              <div className="px-4 py-3 border-b">
                <p className="font-bold text-gray-700 text-sm">Categories</p>
              </div>
              <div className="py-2">
                {categories.map((cat) => (
                  <button
                    key={cat}
                    onClick={() => setCategory(cat)}
                    className={`w-full flex items-center gap-3 px-4 py-2.5 text-sm transition text-left ${
                      category === cat
                        ? 'bg-primary/10 text-primary font-semibold border-r-4 border-primary'
                        : 'text-gray-600 hover:bg-gray-50'
                    }`}
                  >
                    <span className="text-lg">{categoryIcons[cat]}</span>
                    {cat}
                  </button>
                ))}
              </div>
            </div>
          </aside>

          <main className="flex-1">
            <div className="relative overflow-hidden rounded-2xl mb-6 h-56 sm:h-64 lg:h-72">
              <div className={`absolute inset-0 bg-gradient-to-r ${carouselSlides[carouselIndex].className} transition-all duration-700`} />
              <div className="absolute inset-0 bg-black/25" />
              <div className="relative z-10 p-6 sm:p-8 h-full flex flex-col justify-center">
                <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold text-white tracking-wide mb-2">{carouselSlides[carouselIndex].title}</h1>
                <p className="text-white/90 text-sm sm:text-base">{carouselSlides[carouselIndex].subtitle}</p>
              </div>
              <div className="absolute bottom-4 left-1/2 -translate-x-1/2 flex gap-2">
                {carouselSlides.map((_, idx) => (
                  <button
                    key={idx}
                    onClick={() => setCarouselIndex(idx)}
                    className={`w-2 h-2 rounded-full ${carouselIndex === idx ? 'bg-white' : 'bg-white/50'}`}
                    aria-label={`Go to slide ${idx + 1}`}
                  />
                ))}
              </div>
            </div>

            {isCategoryView ? (
              <section className="mb-12">
                <div className="mb-4 flex items-center justify-between">
                  <h2 className="text-2xl font-bold text-primary">{category} Products</h2>
                  <p className="text-sm text-gray-500">{categoryListings.length} products found</p>
                </div>
                {loading ? (
                  <div className="text-center py-8 text-gray-400">Loading products...</div>
                ) : categoryListings.length === 0 ? (
                  <div className="text-center py-8 text-gray-400">No products in this category.</div>
                ) : (
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                    {categoryListings.map((product) => (
                      <ProductCard key={product._id} product={product} />
                    ))}
                  </div>
                )}
              </section>
            ) : (
              <>
                <section className="mb-6">
                  <div className="mb-4 flex items-center justify-between">
                    <h2 className="text-2xl font-bold text-primary">Featured Products</h2>
                    <p className="text-sm text-gray-500">Popular picks from local producers</p>
                  </div>
                  {loading ? (
                    <div className="text-center py-8 text-gray-400">Loading...</div>
                  ) : featuredProducts.length === 0 ? (
                    <div className="text-center py-8 text-gray-400">No featured products available.</div>
                  ) : (
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                      {featuredProducts.map((product) => (
                        <ProductCard key={`featured-${product._id}`} product={product} />
                      ))}
                    </div>
                  )}
                </section>

                <section className="mb-6">
                  <div className="mb-4 flex items-center justify-between">
                    <h2 className="text-2xl font-bold text-primary">SAGANA Price Drop</h2>
                    <p className="text-sm text-gray-500">Seasonal discounts from top categories</p>
                  </div>
                  {loadingPriceDrops ? (
                    <div className="text-center py-8 text-gray-400">Loading price drops...</div>
                  ) : dealsProducts.length === 0 ? (
                    <div className="text-center py-8 text-gray-400">No deals currently.</div>
                  ) : (
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                      {dealsProducts.map((product) => (
                        <ProductCard key={`deal-${product._id}`} product={product} />
                      ))}
                    </div>
                  )}
                </section>

                <section className="mb-12">
                  <div className="mb-4 flex items-center justify-between">
                    <h2 className="text-2xl font-bold text-primary">All Products</h2>
                    <p className="text-sm text-gray-500">{filteredProducts.length} products available</p>
                  </div>
                  {loading ? (
                    <div className="text-center py-8 text-gray-400">Loading products...</div>
                  ) : filteredProducts.length === 0 ? (
                    <div className="text-center py-8 text-gray-400">No products match your search.</div>
                  ) : (
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                      {filteredProducts.map((product) => (
                        <ProductCard key={product._id} product={product} />
                      ))}
                    </div>
                  )}
                </section>
              </>
            )}
          </main>
        </div>
        <footer className="bg-white border-t mt-4">
          <div className="max-w-7xl mx-auto px-4 py-8 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 text-sm text-gray-600">
            <div>
              <h3 className="font-bold text-gray-800 mb-2">SAGANA</h3>
              <p>Fresh produce and daily essentials delivered to your door.</p>
            </div>
            <div>
              <h3 className="font-semibold text-gray-800 mb-2">Help & Policies</h3>
              <ul className="space-y-1">
                <li><a className="hover:text-primary" href="/terms">Terms</a></li>
                <li><a className="hover:text-primary" href="/faq">FAQs</a></li>
                <li><a className="hover:text-primary" href="/contact">Contact Us</a></li>
              </ul>
            </div>
            <div>
              <h3 className="font-semibold text-gray-800 mb-2">Account & Privacy</h3>
              <ul className="space-y-1">
                <li><a className="hover:text-primary" href="/account">My Account</a></li>
                <li><a className="hover:text-primary" href="/privacy">Privacy Policy</a></li>
                <li><a className="hover:text-primary" href="/cookies">Cookies</a></li>
              </ul>
            </div>
          </div>
          <div className="border-t mt-4 pt-3 text-center text-xs text-gray-500">© {new Date().getFullYear()} SAGANA Marketplace. All rights reserved.</div>
        </footer>
      </div>
    </PageWrapper>
  );
};

export default Marketplace;