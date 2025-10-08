# Asset Optimization Guide

## Overview

Gravikon uses **Propshaft** (Rails 8 default) for asset management with custom minification via **Terser** (JavaScript) and **CSSO** (CSS).

## Production Asset Pipeline

### 1. Minification Process

Assets are minified using a custom Rake task that processes all CSS and JavaScript files:

```bash
# Minify all assets for production
rails assets:minify

# Or use the standard Rails command (aliased)
rails assets:precompile
```

### 2. How It Works

**JavaScript Minification (Terser):**
- Removes whitespace and comments
- Mangles variable names
- Applies 2-pass compression
- Expected reduction: 40-60%

**CSS Minification (CSSO):**
- Removes whitespace and comments
- Optimizes CSS structure
- Merges duplicate rules
- Expected reduction: 30-50%

### 3. Output Structure

```
app/assets/
├── javascripts/
│   ├── keyboard_shortcuts.js (5.6 KB)
│   ├── meeting_form.js (5.9 KB)
│   ├── orbital_animation.js (9.8 KB)
│   ├── relativistic_viz.js (2.5 KB)
│   └── system_map.js (3.5 KB)
└── stylesheets/
    ├── application.css (759 bytes)
    └── gravikon.css (25 KB)

↓ minification ↓

public/assets/
├── javascripts/
│   ├── keyboard_shortcuts.js (~2.8 KB)
│   ├── meeting_form.js (~3.0 KB)
│   ├── orbital_animation.js (~4.9 KB)
│   ├── relativistic_viz.js (~1.3 KB)
│   └── system_map.js (~1.8 KB)
└── stylesheets/
    ├── application.css (~500 bytes)
    └── gravikon.css (~17 KB)
```

### 4. Compression (Thruster)

After minification, **Thruster** provides HTTP-level compression:

- **Gzip**: ~70% additional reduction
- **Brotli**: ~75% additional reduction (if supported)

**Total reduction cascade:**
```
Original:    53 KB (unminified)
Minified:    ~26 KB (50% reduction)
Gzipped:     ~8 KB  (85% total reduction)
Brotli:      ~6 KB  (89% total reduction)
```

## Performance Targets

### Page Load Budget: <500 KB

**Asset Breakdown:**
- JavaScript (minified): ~14 KB
- CSS (minified): ~18 KB
- Google Fonts: ~50-100 KB (external, cached)
- SVG system map: Variable (generated)
- HTML: ~10-20 KB

**Total first load:** ~150-200 KB (minified + gzipped)

✅ **Well within 500 KB target**

## Deployment Checklist

### Before Deploying to Production:

1. **Install minification gems:**
   ```bash
   bundle install
   ```

2. **Run minification:**
   ```bash
   RAILS_ENV=production rails assets:minify
   ```

3. **Verify output:**
   ```bash
   ls -lh public/assets/javascripts/
   ls -lh public/assets/stylesheets/
   ```

4. **Check total size:**
   ```bash
   du -sh public/assets/
   ```

5. **Commit minified assets** (if not using CI/CD):
   ```bash
   git add public/assets/
   git commit -m "Add minified production assets"
   ```

### Using Kamal (Docker):

Add to `config/deploy.yml`:

```yaml
# Run asset minification during build
builder:
  args:
    RAILS_ENV: production
  cache:
    type: registry

  # Run minification in Dockerfile
  dockerfile: Dockerfile

  hooks:
    pre-build:
      - rails assets:minify
```

## Development vs Production

### Development (Unminified)

- Serves files directly from `app/assets/`
- No minification for easier debugging
- Source maps available
- Hot reloading if configured

### Production (Minified)

- Serves files from `public/assets/`
- Fully minified with Terser/CSSO
- Gzip/Brotli compressed via Thruster
- Cache headers for 1 year

## Verification Commands

### Check Minification Effectiveness

```bash
# Run minification with detailed output
rails assets:minify

# Compare sizes
ls -lh app/assets/javascripts/*.js
ls -lh public/assets/javascripts/*.js
```

### Test Gzip Compression

```bash
# Start production server with Thruster
RAILS_ENV=production rails server

# Test with curl
curl -H "Accept-Encoding: gzip" -I http://localhost:3000/assets/javascripts/orbital_animation.js
```

Expected response:
```
Content-Encoding: gzip
Content-Length: ~2000 (vs 9800 uncompressed)
```

## Cleaning Assets

```bash
# Remove minified assets
rails assets:clean_minified

# Or manually
rm -rf public/assets/
```

## Troubleshooting

### Issue: Assets not minified in production

**Solution:**
```bash
RAILS_ENV=production rails assets:minify
```

### Issue: Old assets being served

**Solution:**
```bash
rails assets:clean_minified
rails assets:minify
```

### Issue: Minification errors

**Check JavaScript syntax:**
```bash
node -c app/assets/javascripts/filename.js
```

**Check CSS syntax:**
```bash
csslint app/assets/stylesheets/filename.css
```

## Performance Monitoring

### Measure Page Load Size

```javascript
// In browser console
console.log(
  'Total page size:',
  performance.getEntriesByType('resource')
    .reduce((sum, r) => sum + r.transferSize, 0) / 1024,
  'KB'
);
```

### Lighthouse Audit

```bash
# Install Lighthouse CLI
npm install -g lighthouse

# Run audit
lighthouse http://localhost:3000 --view
```

## Future Optimizations

1. **Bundle splitting**: Separate vendor and app code
2. **Code splitting**: Load JS modules on demand
3. **Image optimization**: Use WebP format
4. **Font subsetting**: Include only used glyphs
5. **Service Worker**: Offline caching with Workbox
6. **HTTP/2 Push**: Preload critical assets
7. **CDN**: Serve static assets from edge network

## References

- [Propshaft Documentation](https://github.com/rails/propshaft)
- [Terser Options](https://github.com/terser/terser#minify-options)
- [CSSO Documentation](https://github.com/css/csso)
- [Thruster Compression](https://github.com/basecamp/thruster)
- [Web Performance Best Practices](https://web.dev/fast/)
