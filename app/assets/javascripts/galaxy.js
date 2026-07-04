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

          // Navigate to system show page
          // Try to use Turbo if available, otherwise fall back to standard navigation
          const url = `/galaxy/systems/${systemId}`;

          if (typeof Turbo !== 'undefined' && Turbo.visit) {
            Turbo.visit(url);
          } else {
            window.location.href = url;
          }
        });

        // Add visual feedback on hover
        marker.addEventListener('mouseenter', () => {
          marker.style.opacity = '0.8';
          marker.style.transform = 'scale(1.1)';
          marker.style.transition = 'all 0.2s ease';
        });

        marker.addEventListener('mouseleave', () => {
          marker.style.opacity = '1';
          marker.style.transform = 'scale(1)';
        });
      });

      if (window.Logger) window.Logger.log(`Initialized navigation for ${systemMarkers.length} system markers`);
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

      systemMarkers.forEach(marker => {
        marker.addEventListener('mouseenter', (e) => {
          const systemName = marker.getAttribute('data-system-name') || 'Neznámá soustava';
          const bodyCount = marker.getAttribute('data-body-count') || '0';
          const x = marker.getAttribute('data-x') || '0';
          const y = marker.getAttribute('data-y') || '0';
          const totalMass = marker.getAttribute('data-total-mass') || '0';

          // Calculate distance from black hole (center at 400, 400)
          const distance = Math.sqrt(
            Math.pow(parseFloat(x) - 400, 2) +
            Math.pow(parseFloat(y) - 400, 2)
          ).toFixed(1);

          // Format total mass
          const massFormatted = parseFloat(totalMass).toExponential(2);

          // Build tooltip content
          tooltip.innerHTML = `
            <strong>${systemName}</strong><br>
            Počet těles: ${bodyCount}<br>
            Pozice: (${parseFloat(x).toFixed(1)}, ${parseFloat(y).toFixed(1)})<br>
            Vzdálenost od černé díry: ${distance}<br>
            Celková hmotnost: ${massFormatted} kg<br>
            <em style="font-size: 0.85em; opacity: 0.8;">Klikněte pro zobrazení</em>
          `;

          tooltip.style.display = 'block';
          this.positionTooltip(e, tooltip);
        });

        marker.addEventListener('mousemove', (e) => {
          this.positionTooltip(e, tooltip);
        });

        marker.addEventListener('mouseleave', () => {
          tooltip.style.display = 'none';
        });
      });

      if (window.Logger) window.Logger.log('Initialized tooltips for system markers');
    },

    // Position tooltip near cursor, preventing off-screen positioning
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

  // Re-initialize on Turbo navigation if available
  if (typeof Turbo !== 'undefined') {
    document.addEventListener('turbo:load', () => GalaxyInteractions.init());
  }

  // Export for external access if needed
  window.GalaxyInteractions = GalaxyInteractions;
})();
