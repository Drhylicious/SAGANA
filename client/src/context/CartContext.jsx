import React, { createContext, useContext, useState, useEffect } from 'react';

const CartContext = createContext();

export const useCart = () => useContext(CartContext);


export const CartProvider = ({ children }) => {
  const [cart, setCart] = useState(() => {
    const saved = localStorage.getItem('cart');
    return saved ? JSON.parse(saved) : [];
  });

  // Persist cart to localStorage
  useEffect(() => {
    localStorage.setItem('cart', JSON.stringify(cart));
  }, [cart]);

  // Listen for logout event to clear cart from state
  useEffect(() => {
    const clear = () => setCart([]);
    window.addEventListener('cart:clear', clear);
    return () => window.removeEventListener('cart:clear', clear);
  }, []);

  // Accepts product and inventoryBatch
  const addToCart = (product, inventoryBatch) => {
    // Normalize image URL
    let imageUrl = product.image;
    if (imageUrl && !imageUrl.startsWith('http')) {
      imageUrl = `${import.meta.env.VITE_API_URL?.replace('/api/v1','') || 'http://localhost:5000'}${imageUrl}`;
    }
    const productWithImage = { ...product, image: imageUrl };
    const existing = cart.find(
      (item) => item._id === product._id && item.inventoryBatch === inventoryBatch
    );
    if (existing) {
      setCart(
        cart.map((item) =>
          item._id === product._id && item.inventoryBatch === inventoryBatch
            ? { ...item, qty: item.qty + 1 }
            : item
        )
      );
    } else {
      setCart([...cart, { ...productWithImage, qty: 1, inventoryBatch }]);
    }
  };


  const removeFromCart = (id) => {
    setCart(cart.filter((item) => item._id !== id));
  };

  const increaseQty = (id) => {
    setCart(cart.map((item) =>
      item._id === id ? { ...item, qty: item.qty + 1 } : item
    ));
  };

  const decreaseQty = (id) => {
    setCart(cart.map((item) =>
      item._id === id ? { ...item, qty: Math.max(1, item.qty - 1) } : item
    ));
  };

  const clearCart = () => {
    setCart([]);
    localStorage.removeItem('cart');
  };

  return (
    <CartContext.Provider value={{ cart, addToCart, removeFromCart, clearCart, increaseQty, decreaseQty }}>
      {children}
    </CartContext.Provider>
  );
};
