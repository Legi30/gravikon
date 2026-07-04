// Galaxy Map Interactive Features
// Handles interactions with the galaxy visualization including system navigation,
// tooltips, and position selection for new systems

(function() {
  'use strict';

  // Galaxy interaction manager
  const GalaxyInteractions = {
    // Initialize all galaxy interactions
    init() {
      this.initSystemNavigation();
      this.initSystemTooltips();
      this.initGalaxyOrbits();
      this.initPositionSelector();

      if (window.Logger) window.Logger.log('Galaxy interactions initialized');
    },

    // Initialize click navigation on system markers
    initSystemNavigation() {
      const systemMarkers = document.querySelectorAll('.system-marker');

      if (systemMarkers.length === 0) {
        if (window.Logger) window.Logger.info('No system markers found for navigation');
        return;
      }

      systemMarkers.forEach(marker => {
        marker.addEventListener('click', (e) => {
          const systemId = marker.getAttribute('data-system-id');

          if (!systemId) {
            if (window.Logger) window.Logger.warn('System marker missing data-system-id');
            return;
          }

          window.location.href = `/galaxy/systems/${systemId}`;
        });
      });

      if (window.Logger) window.Logger.log(`Initialized navigation for ${systemMarkers.length} system markers`);
    },

    // Real-time orbit animation: systems revolve around the black hole.
    // Positions derive from wall-clock time, so a refresh continues the
    // motion instead of resetting it.
    initGalaxyOrbits() {
      const markers = Array.from(document.querySelectorAll('#solar-systems .system-marker'));
      if (markers.length === 0) return;

      const CENTER_X = 400;
      const CENTER_Y = 400;

      const orbiting = markers.map(marker => ({
        marker: marker,
        orbitRadius: parseFloat(marker.getAttribute('data-orbit-radius')) || 0,
        initialAngle: parseFloat(marker.getAttribute('data-initial-angle')) || 0,
        orbitalPeriod: parseFloat(marker.getAttribute('data-orbital-period')) || 0
      })).filter(m => m.orbitRadius > 1 && m.orbitalPeriod > 0);

      if (orbiting.length === 0) return;

      function tick() {
        const epochSeconds = Date.now() / 1000;

        orbiting.forEach(m => {
          const angle = m.initialAngle + (2 * Math.PI * epochSeconds) / m.orbitalPeriod;
          const x = CENTER_X + m.orbitRadius * Math.cos(angle);
          const y = CENTER_Y + m.orbitRadius * Math.sin(angle);
          m.marker.setAttribute('transform', `translate(${x.toFixed(2)}, ${y.toFixed(2)})`);
        });

        requestAnimationFrame(tick);
      }

      requestAnimationFrame(tick);
      if (window.Logger) window.Logger.log(`Galaxy orbit animation running for ${orbiting.length} systems`);
    },

    // Initialize tooltips for system markers
    initSystemTooltips() {
      const tooltip = document.getElementById('tooltip');
      const systemMarkers = document.querySelectorAll('.system-marker');

      if (!tooltip) {
        if (window.Logger) window.Logger.info('Tooltip element not found');
        return;
      }

      if (systemMarkers.length === 0) {
        return;
      }

      // Same behaviour as celestial bodies in the system view (system_map.js):
      // highlight on hover, tooltip follows the cursor below-right.
      systemMarkers.forEach(marker => {
        const core = marker.querySelector('.system-core');
        const originalStroke = core ? core.getAttribute('stroke') : null;
        const originalStrokeWidth = core ? core.getAttribute('stroke-width') : null;

        marker.addEventListener('mouseover', (e) => {
          if (core) {
            core.setAttribute('stroke', '#ffd700');
            core.setAttribute('stroke-width', '3');
          }

          const systemName = marker.getAttribute('data-system-name') || 'Neznámá soustava';
          const bodyCount = marker.getAttribute('data-body-count') || '0';
          const orbitRadius = parseFloat(marker.getAttribute('data-orbit-radius')) || 0;

          tooltip.innerHTML = `
            <div class="tooltip-title">${systemName}</div>
            <div class="tooltip-row"><span>Počet těles</span><span>${bodyCount}</span></div>
            <div class="tooltip-row"><span>Vzdálenost od černé díry</span><span>${orbitRadius.toFixed(0)} j.</span></div>
            <div class="tooltip-hint">Klikněte pro detail soustavy</div>
          `;

          tooltip.style.display = 'block';
          this.positionTooltip(e, tooltip);
        });

        marker.addEventListener('mousemove', (e) => {
          this.positionTooltip(e, tooltip);
        });

        marker.addEventListener('mouseout', () => {
          if (core) {
            core.setAttribute('stroke', originalStroke);
            core.setAttribute('stroke-width', originalStrokeWidth);
          }
          tooltip.style.display = 'none';
        });
      });

      if (window.Logger) window.Logger.log('Initialized tooltips for system markers');
    },

    // Position tooltip near cursor (identical to system_map.js), preventing
    // off-screen placement.
    positionTooltip(event, tooltip) {
      const offsetX = 15;
      const offsetY = 15;

      let x = event.clientX + offsetX;
      let y = event.clientY + offsetY;

      const tooltipRect = tooltip.getBoundingClientRect();
      const viewportWidth = window.innerWidth;
      const viewportHeight = window.innerHeight;

      if (x + tooltipRect.width > viewportWidth) {
        x = event.clientX - tooltipRect.width - offsetX;
      }
      if (y + tooltipRect.height > viewportHeight) {
        y = event.clientY - tooltipRect.height - offsetY;
      }

      tooltip.style.left = x + 'px';
      tooltip.style.top = y + 'px';
    },

    // Initialize click-to-select position in galaxy for new systems
    initPositionSelector() {
      const positionPreview = document.getElementById('position-preview');
      const xField = document.getElementById('system_x');
      const yField = document.getElementById('system_y');

      if (!positionPreview || !xField || !yField) {
        if (window.Logger) window.Logger.info('Position selector elements not found (not on new/edit page)');
        return;
      }

      const svg = positionPreview.querySelector('svg');
      if (!svg) return;

      // Create a selection marker if it doesn't exist
      let selectionMarker = svg.querySelector('#position-selection-marker');
      if (!selectionMarker) {
        const svgNS = 'http://www.w3.org/2000/svg';
        selectionMarker = document.createElementNS(svgNS, 'circle');
        selectionMarker.setAttribute('id', 'position-selection-marker');
        selectionMarker.setAttribute('r', '15');
        selectionMarker.setAttribute('fill', '#10b981');
        selectionMarker.setAttribute('stroke', '#059669');
        selectionMarker.setAttribute('stroke-width', '2');
        selectionMarker.setAttribute('opacity', '0.8');
        selectionMarker.style.display = 'none';
        svg.appendChild(selectionMarker);
      }

      // Handle clicks on SVG to select position
      svg.addEventListener('click', (e) => {
        const rect = svg.getBoundingClientRect();
        const clickX = e.clientX - rect.left;
        const clickY = e.clientY - rect.top;

        // Convert click coordinates to SVG coordinates (viewBox is 0 0 800 800)
        const svgX = (clickX / rect.width) * 800;
        const svgY = (clickY / rect.height) * 800;

        // Validate position
        const validation = this.validatePosition(svgX, svgY);

        if (validation.valid) {
          // Update form fields
          xField.value = svgX.toFixed(1);
          yField.value = svgY.toFixed(1);

          // Update selection marker
          selectionMarker.setAttribute('cx', svgX);
          selectionMarker.setAttribute('cy', svgY);
          selectionMarker.style.display = 'block';

          // Trigger input event to update form validation
          xField.dispatchEvent(new Event('input', { bubbles: true }));
          yField.dispatchEvent(new Event('input', { bubbles: true }));

          if (window.Logger) window.Logger.log(`Position selected: (${svgX.toFixed(1)}, ${svgY.toFixed(1)})`);
        } else {
          // Show error feedback
          this.showPositionError(validation.error);
        }
      });

      // Add visual feedback on hover
      svg.style.cursor = 'crosshair';

      if (window.Logger) window.Logger.log('Initialized position selector');
    },

    // Validate position is safe (not too close to black hole or edge)
    validatePosition(x, y) {
      const MIN_DISTANCE_FROM_BLACK_HOLE = 50;
      const RECOMMENDED_MIN = 100;
      const RECOMMENDED_MAX = 700;
      const BLACK_HOLE_X = 400;
      const BLACK_HOLE_Y = 400;

      // Check canvas bounds
      if (x < 0 || x > 800 || y < 0 || y > 800) {
        return { valid: false, error: 'Pozice je mimo platnou oblast (0-800)' };
      }

      // Check distance from black hole
      const distance = Math.sqrt(
        Math.pow(x - BLACK_HOLE_X, 2) +
        Math.pow(y - BLACK_HOLE_Y, 2)
      );

      if (distance < MIN_DISTANCE_FROM_BLACK_HOLE) {
        return {
          valid: false,
          error: `Pozice je příliš blízko černé díry (vzdálenost: ${distance.toFixed(1)}, minimum: ${MIN_DISTANCE_FROM_BLACK_HOLE})`
        };
      }

      // Warning for positions outside recommended range (but still allow)
      if (x < RECOMMENDED_MIN || x > RECOMMENDED_MAX || y < RECOMMENDED_MIN || y > RECOMMENDED_MAX) {
        if (window.Logger) window.Logger.warn('Position outside recommended range but still valid');
      }

      return { valid: true };
    },

    // Show position validation error
    showPositionError(message) {
      // Try to find validation display element
      const validationDisplay = document.getElementById('position-validation');

      if (validationDisplay) {
        validationDisplay.style.display = 'block';
        validationDisplay.style.background = 'rgba(231, 76, 60, 0.1)';
        validationDisplay.style.border = '1px solid #e74c3c';
        validationDisplay.style.color = '#e74c3c';
        validationDisplay.innerHTML = `❌ <strong>Chyba:</strong> ${message}`;
      } else {
        // Fallback to alert
        alert(`Neplatná pozice: ${message}`);
      }
    }
  };

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => GalaxyInteractions.init());
  } else {
    GalaxyInteractions.init();
  }

  // Export for external access if needed
  window.GalaxyInteractions = GalaxyInteractions;
})();
