// Orbital Animation Engine — real-time synchronous mode
//
// Body positions are a pure function of wall-clock time:
//   angle = initialAngle + 2π × (epochSeconds / orbitalPeriod)
// so a page refresh (or another browser) shows the orbits exactly where
// they "really" are — the animation continues instead of restarting.
// Pausing only freezes the display; resuming jumps to the current
// real-time position (the system "catches up").

class OrbitalAnimator {
  constructor() {
    this.isAnimating = false;
    this.animationId = null;
    this.bodies = [];
    this.bodyLookup = {};

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
      const radius = parseFloat(element.getAttribute('r')) || 5;

      // Find orbit path element for this body (if it exists)
      const orbitPath = document.querySelector(`.orbit-path[data-body-name="${bodyName}"]`);

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
        originalX: originalX,
        originalY: originalY,
        // No parent name = orbits a fixed point (a binary's common centre)
        hasOrbit: orbitRadius > 0 && orbitalPeriod > 0,
        currentX: originalX,
        currentY: originalY,
        orbitPath: orbitPath
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

    if (window.Logger) window.Logger.log(`Initialized real-time orbital animation for ${this.bodies.length} bodies`);
    return true;
  }

  start() {
    if (this.isAnimating) return;

    this.isAnimating = true;
    this.animate();

    if (window.Logger) window.Logger.log('Orbital animation running (real-time)');
  }

  pause() {
    if (!this.isAnimating) return;

    this.isAnimating = false;

    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }

    if (window.Logger) window.Logger.log('Orbital animation paused (will catch up on resume)');
  }

  animate() {
    if (!this.isAnimating) return;

    const now = performance.now();

    // Positions derive from wall-clock time — identical across refreshes
    const epochSeconds = Date.now() / 1000;

    // FPS monitoring
    this.frameCount++;
    if (now - this.lastFpsUpdate >= 1000) {
      this.currentFps = Math.round(this.frameCount * 1000 / (now - this.lastFpsUpdate));
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
      this.lastFpsUpdate = now;
    }

    // Batch DOM updates: pre-calculate all positions, then update DOM
    const updates = [];

    for (let i = 0; i < this.bodies.length; i++) {
      const body = this.bodies[i];

      if (!body.hasOrbit) {
        // Star or non-orbiting body - keep at original position
        body.currentX = body.originalX;
        body.currentY = body.originalY;
        continue;
      }

      // A hovered body is frozen (system_map.js) so it cannot slide out
      // from under the cursor; it catches up to real time on mouseout.
      // Its moons keep orbiting the frozen position (currentX/Y unchanged).
      if (body.element.__orbitFrozen) continue;

      // Real-time angle: full revolutions since epoch plus the body's phase
      const currentAngle = body.initialAngle + (2 * Math.PI * epochSeconds) / body.orbitalPeriod;

      // Get parent's current position (for moons orbiting planets that are also moving)
      let parentX = body.parentX;
      let parentY = body.parentY;

      if (body.parentName && this.bodyLookup[body.parentName]) {
        const parentBody = this.bodyLookup[body.parentName];
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

    // Update orbit paths for moons (their orbit circles follow parent planets)
    for (let i = 0; i < this.bodies.length; i++) {
      const body = this.bodies[i];

      if (body.type === 'moon' && body.orbitPath && body.parentName) {
        const parentBody = this.bodyLookup[body.parentName];
        if (parentBody) {
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
      // Set up play/pause control if it exists
      const playPauseBtn = document.getElementById('orbit-play-pause');

      if (playPauseBtn) {
        playPauseBtn.addEventListener('click', function() {
          orbitalAnimator.toggle();
          updatePlayPauseButton();
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

// Global function to check animation performance (for console/debugging)
window.getAnimationPerformance = function() {
  if (!orbitalAnimator) {
    if (window.Logger) window.Logger.log('Animation not initialized');
    return null;
  }

  const report = orbitalAnimator.getPerformanceReport();
  if (window.Logger) {
    window.Logger.log(`FPS: ${report.currentFps} (avg ${report.averageFps}), bodies: ${report.bodiesAnimated}/${report.totalBodies}, ${report.performance}`);
  }

  return report;
};
