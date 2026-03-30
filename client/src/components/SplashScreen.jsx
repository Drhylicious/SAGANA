import { motion } from 'framer-motion';
import logo from '../assets/logo.jpg';

const SplashScreen = ({ onComplete }) => {
  return (
    <motion.div
      className="fixed inset-0 bg-white flex flex-col items-center justify-center z-50"
      initial={{ opacity: 1 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
    >
      {/* Logo Image */}
      <motion.img
        src={logo}
        alt="SAGANA Logo"
        className="w-64 h-64 object-contain"
        initial={{ scale: 0.5, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.7, ease: "easeOut" }}
      />

      {/* Tagline */}
      <motion.p
        initial={{ y: 20, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ delay: 0.6, duration: 0.6 }}
        className="text-gray-500 text-base mt-2 text-center px-8"
      >
        Empowering the Cooperatives of Boac, Marinduque
      </motion.p>

      {/* Loading bar */}
      <motion.div
        className="mt-8 w-48 h-1 bg-gray-200 rounded-full overflow-hidden"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.8 }}
      >
        <motion.div
          className="h-full bg-primary rounded-full"
          initial={{ width: "0%" }}
          animate={{ width: "100%" }}
          transition={{ delay: 0.9, duration: 1.2, ease: "easeInOut" }}
          onAnimationComplete={onComplete}
        />
      </motion.div>
    </motion.div>
  );
};

export default SplashScreen;