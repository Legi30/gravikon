// Orbital Animation Engine
// Animates celestial bodies along their orbits using requestAnimationFrame

class OrbitalAnimator {
  constructor() {
    this.isAnimating = false;
    this.animationId = null;
    this.startTime = null;
    this.pausedTime = 0;
    this.bodies = [];
    this.speedMultiplier = 1.0; // Animation speed control

    // FPS monitoring
    this.frameCount = 0;
    this.lastFpsUpdate = 0;
    this.currentFps = 60;
    this.fpsHistory = [];
    this.lowFpsWarningShown = false;
  }

  initialize() {
    // Find all celestial bodies in the SVG
    const celestialBodies = document.querySelectorAll('.celestial-body');

    if (celestialBodies.length === 0) {
      if (window.Logger) window.Logger.warn('No celestial bodies found for animation');
      return false;
    }

    // Parse body data and store initial states
    this.bodies = Array.from(celestialBodies).map(element => {
      const bodyName = element.getAttribute('data-name');
      const parentName = element.getAttribute('data-parent');
      const orbitRadius = parseFloat(element.getAttribute('data-orbit-radius')) || 0;
      const parentX = parseFloat(element.getAttribute('data-parent-x')) || 0;
      const parentY = parseFloat(element.getAttribute('data-parent-y')) || 0;
      const initialAngle = parseFloat(element.getAttribute('data-initial-angle')) || 0;
      const orbitalPeriod = parseFloat(element.getAttribute('data-orbital-period')) || 0;
      const bodyType = element.getAttribute('data-type');

      // Store original position
      const originalX = parseFloat(element.getAttribute('cx'));
      const originalY = parseFloat(element.getAttribute('cy'));

      // Pre-cache text element reference to avoid DOM traversal every frame
      const textElement = element.nextElementSibling;
      const hasTextLabel = textElement && textElement.tagName === 'text';
      const radius = hasTextLabel ? parseFloat(element.getAttribute('r')) || 5 : 0;

      // Pre-calculate angular velocity (constant per body)
      const angularVelocity = orbitalPeriod > 0 ? (2 * Math.PI) / orbitalPeriod : 0;

      // Find orbit path element for this body (if it exists)
      const orbitPath = document.querySelector(`.orbit-path[data-body-name="${bodyName}"]`);
      const orbitPathOriginalX = orbitPath ? parseFloat(orbitPath.getAttribute('cx')) : 0;
      const orbitPathOriginalY = orbitPath ? parseFloat(orbitPath.getAttribute('cy')) : 0;

      return {
        element: element,
        textElement: hasTextLabel ? textElement : null,
        radius: radius,
        type: bodyType,
        name: bodyName,
        parentName: parentName,
        parentX: parentX,
        parentY: parentY,
        orbitRadius: orbitRadius,
        initialAngle: initialAngle,
        orbitalPeriod: orbitalPeriod,
        angularVelocity: angularVelocity,
        originalX: originalX,
        originalY: originalY,
        hasOrbit: orbitRadius > 0 && parentName !== "",
        currentX: originalX,
        currentY: originalY,
        orbitPath: orbitPath,
        orbitPathOriginalX: orbitPathOriginalX,
        orbitPathOriginalY: orbitPathOriginalY
      };
    });

    // Sort bodies to ensure parents are processed before children
    // Order: star -> planet -> moon
    const typeOrder = { 'star': 0, 'planet': 1, 'moon': 2 };
    this.bodies.sort((a, b) => {
      const orderA = typeOrder[a.type] !== undefined ? typeOrder[a.type] : 999;
      const orderB = typeOrder[b.type] !== undefined ? typeOrder[b.type] : 999;
      return orderA - orderB;
    });

    // Create a lookup map for finding bodies by name
    this.bodyLookup = {};
    this.bodies.forEach(body => {
      if (body.name) {
        this.bodyLookup[body.name] = body;
      }
    });

    if (window.Logger) window.Logger.log(`Initialized orbital animation for ${this.bodies.length} bodies`);
    return true;
  }

  start() {
    if (this.isAnimating) return;

    this.isAnimating = true;
    this.startTime = performance.now() - this.pausedTime;
    this.animate();

    if (window.Logger) window.Logger.log('Orbital animation started');
  }

  pause() {
    if (!this.isAnimating) return;

    this.isAnimating = false;
    this.pausedTime = performance.now() - this.startTime;

    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }

    if (window.Logger) window.Logger.log('Orbital animation paused');
  }

  reset() {
    this.pause();
    this.pausedTime = 0;

    // Reset all bodies to original positions
    this.bodies.forEach(body => {
      body.element.setAttribute('cx', body.originalX);
      body.element.setAttribute('cy', body.originalY);
      body.currentX = body.originalX;
      body.currentY = body.originalY;

      // Reset text labels if they exist
      if (body.textElement) {
        body.textElement.setAttribute('x', body.originalX + body.radius + 5);
        body.textElement.setAttribute('y', body.originalY - body.radius - 5);
      }

      // Reset orbit paths if they exist
      if (body.orbitPath) {
        body.orbitPath.setAttribute('cx', body.orbitPathOriginalX);
        body.orbitPath.setAttribute('cy', body.orbitPathOriginalY);
      }
    });

    if (window.Logger) window.Logger.log('Orbital animation reset');
  }

  setSpeed(multiplier) {
    this.speedMultiplier = Math.max(0.1, Math.min(10, multiplier));
    if (window.Logger) window.Logger.log(`Animation speed set to ${this.speedMultiplier}x`);
  }

  animate() {
    if (!this.isAnimating) return;

    const currentTime = performance.now();
    const elapsedTime = (currentTime - this.startTime) / 1000; // Convert to seconds

    // FPS monitoring
    this.frameCount++;
    if (currentTime - this.lastFpsUpdate >= 1000) {
      this.currentFps = Math.round(this.frameCount * 1000 / (currentTime - this.lastFpsUpdate));
      this.fpsHistory.push(this.currentFps);
      if (this.fpsHistory.length > 10) this.fpsHistory.shift();

      // Update FPS display if element exists
      const fpsDisplay = document.getElementById('fps-display');
      if (fpsDisplay) {
        fpsDisplay.textContent = `${this.currentFps} FPS`;
        fpsDisplay.style.color = this.currentFps >= 55 ? '#11998e' : this.currentFps >= 30 ? '#f5a623' : '#f5576c';
      }

      // Warn if FPS drops below 30 (only once)
      if (this.currentFps < 30 && !this.lowFpsWarningShown) {
        if (window.Logger) window.Logger.warn(`Low frame rate detected: ${this.currentFps} FPS (target: 60 FPS)`);
        this.lowFpsWarningShown = true;
      }

      this.frameCount = 0;
      this.lastFpsUpdate = currentTime;
    }

    // Batch DOM updates using a single reflow
    // Pre-calculate all positions, then update DOM
    const updates = [];

    for (let i = 0; i < this.bodies.length; i++) {
      const body = this.bodies[i];

      if (!body.hasOrbit) {
        // Star or non-orbiting body - keep at original position
        body.currentX = body.originalX;
        body.currentY = body.originalY;
        continue;
      }

      // Calculate current angle using pre-calculated angular velocity
      const currentAngle = body.initialAngle + (body.angularVelocity * elapsedTime * this.speedMultiplier);

      // Get parent's current position (for moons orbiting planets that are also moving)
      let parentX = body.parentX;
      let parentY = body.parentY;

      if (body.parentName && this.bodyLookup[body.parentName]) {
        const parentBody = this.bodyLookup[body.parentName];
        // Use parent's current position if available
        parentX = parentBody.currentX;
        parentY = parentBody.currentY;
      }

      // Calculate new position on orbit relative to parent's current position
      const newX = parentX + body.orbitRadius * Math.cos(currentAngle);
      const newY = parentY + body.orbitRadius * Math.sin(currentAngle);

      // Store current position for children (moons) to reference
      body.currentX = newX;
      body.currentY = newY;

      updates.push({ body, newX, newY });
    }

    // Apply all DOM updates in a single batch
    for (let i = 0; i < updates.length; i++) {
      const { body, newX, newY } = updates[i];

      // Update SVG element position (setAttribute is faster than style for SVG)
      body.element.setAttribute('cx', newX.toFixed(2));
      body.element.setAttribute('cy', newY.toFixed(2));

      // Update text label if exists (using cached reference)
      if (body.textElement) {
        body.textElement.setAttribute('x', (newX + body.radius + 5).toFixed(2));
        body.textElement.setAttribute('y', (newY - body.radius - 5).toFixed(2));
      }
    }

    // Update orbit paths for moons (their orbit circles need to follow parent planets)
    for (let i = 0; i < this.bodies.length; i++) {
      const body = this.bodies[i];

      // Only update orbit paths for moons (type === 'moon')
      if (body.type === 'moon' && body.orbitPath && body.parentName) {
        const parentBody = this.bodyLookup[body.parentName];
        if (parentBody) {
          // Move the moon's orbit circle to follow the parent planet
          body.orbitPath.setAttribute('cx', parentBody.currentX.toFixed(2));
          body.orbitPath.setAttribute('cy', parentBody.currentY.toFixed(2));
        }
      }
    }

    // Continue animation
    this.animationId = requestAnimationFrame(() => this.animate());
  }

  toggle() {
    if (this.isAnimating) {
      this.pause();
    } else {
      this.start();
    }
  }

  // Get current FPS
  getFps() {
    return this.currentFps;
  }

  // Get average FPS over last 10 seconds
  getAverageFps() {
    if (this.fpsHistory.length === 0) return 60;
    return Math.round(this.fpsHistory.reduce((a, b) => a + b, 0) / this.fpsHistory.length);
  }

  // Get performance report
  getPerformanceReport() {
    const avgFps = this.getAverageFps();
    return {
      currentFps: this.currentFps,
      averageFps: avgFps,
      bodiesAnimated: this.bodies.filter(b => b.hasOrbit).length,
      totalBodies: this.bodies.length,
      performance: avgFps >= 55 ? 'Excellent' : avgFps >= 45 ? 'Good' : avgFps >= 30 ? 'Fair' : 'Poor',
      targetMet: avgFps >= 55
    };
  }
}

// Global animator instance
let orbitalAnimator = null;

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
  // Wait a bit to ensure SVG is fully loaded
  setTimeout(() => {
    orbitalAnimator = new OrbitalAnimator();

    if (orbitalAnimator.initialize()) {
      // Set up control buttons if they exist
      const playPauseBtn = document.getElementById('orbit-play-pause');
      const resetBtn = document.getElementById('orbit-reset');
      const speedControl = document.getElementById('orbit-speed');

      if (playPauseBtn) {
        playPauseBtn.addEventListener('click', function() {
          orbitalAnimator.toggle();
          updatePlayPauseButton();
        });
      }

      if (resetBtn) {
        resetBtn.addEventListener('click', function() {
          orbitalAnimator.reset();
          updatePlayPauseButton();
        });
      }

      if (speedControl) {
        speedControl.addEventListener('input', function() {
          const speed = parseFloat(this.value);
          orbitalAnimator.setSpeed(speed);
          updateSpeedLabel(speed);
        });
      }

      // Start animation by default
      orbitalAnimator.start();
      updatePlayPauseButton();
    }
  }, 100);
});

// Helper function to update play/pause button text
function updatePlayPauseButton() {
  const btn = document.getElementById('orbit-play-pause');
  if (btn && orbitalAnimator) {
    if (orbitalAnimator.isAnimating) {
      btn.textContent = '⏸ Pozastavit';
      btn.classList.add('active');
    } else {
      btn.textContent = '▶ Spustit';
      btn.classList.remove('active');
    }
  }
}

// Helper function to update speed label
function updateSpeedLabel(speed) {
  const label = document.getElementById('speed-label');
  if (label) {
    label.textContent = `${speed.toFixed(1)}×`;
  }
}

// Global function to check animation performance (for console/debugging)
window.getAnimationPerformance = function() {
  if (!orbitalAnimator) {
    if (window.Logger) window.Logger.log('Animation not initialized');
    return null;
  }

  const report = orbitalAnimator.getPerformanceReport();
  if (window.Logger) {
    window.Logger.log('='.repeat(60));
    window.Logger.log('ORBITAL ANIMATION PERFORMANCE REPORT');
    window.Logger.log('='.repeat(60));
    window.Logger.log(`Current FPS:      ${report.currentFps}`);
    window.Logger.log(`Average FPS:      ${report.averageFps} (last 10 seconds)`);
    window.Logger.log(`Bodies Animated:  ${report.bodiesAnimated}/${report.totalBodies}`);
    window.Logger.log(`Performance:      ${report.performance}`);
    window.Logger.log(`60 FPS Target:    ${report.targetMet ? '✓ MET' : '✗ NOT MET'}`);
    window.Logger.log('='.repeat(60));

    if (report.averageFps < 55) {
      window.Logger.warn('⚠️  Animation is not maintaining 60 FPS');
      window.Logger.warn('   Recommendations:');
      window.Logger.warn('   - Check Chrome DevTools Performance tab');
      window.Logger.warn('   - Reduce number of celestial bodies');
      window.Logger.warn('   - Close other browser tabs/applications');
    } else {
      window.Logger.log('✅ Animation performance is excellent');
    }
  }

  return report;
};
