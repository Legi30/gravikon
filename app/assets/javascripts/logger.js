// Production-Safe Logger
// Only logs in development, silent in production

const Logger = {
  // Check if we're in development mode
  isDevelopment() {
    // Check Rails environment if available
    if (typeof window.railsEnv !== 'undefined') {
      return window.railsEnv === 'development';
    }
    // Check hostname (localhost = development)
    return window.location.hostname === 'localhost' ||
           window.location.hostname === '127.0.0.1' ||
           window.location.hostname.includes('.local');
  },

  log(...args) {
    if (this.isDevelopment() && console.log) {
      console.log(...args);
    }
  },

  warn(...args) {
    if (this.isDevelopment() && console.warn) {
      console.warn(...args);
    }
  },

  error(...args) {
    // Always log errors, even in production
    if (console.error) {
      console.error(...args);
    }
  },

  info(...args) {
    if (this.isDevelopment() && console.info) {
      console.info(...args);
    }
  },

  // Performance logging (development only)
  performance(label, fn) {
    if (this.isDevelopment() && console.time) {
      console.time(label);
      const result = fn();
      console.timeEnd(label);
      return result;
    } else {
      return fn();
    }
  }
};

// Export for use in other files
window.Logger = Logger;
