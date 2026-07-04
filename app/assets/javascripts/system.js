// System View Interactive Features
// Extends system_map.js with additional interactions for system views
// Handles body selection for meetings and enhanced visualizations

(function() {
  'use strict';

  // System view interaction manager
  const SystemInteractions = {
    selectedBodies: [],
    maxSelections: null,
    animationActive: false,
    animationId: null,
    animationStartTime: null,
    bodies: [],
    bodyLookup: {},

    // Initialize all system interactions
    init() {
      this.initBodySelection();
      this.initEnhancedTooltips();
      this.initOrbitalAnimation();
      this.syncWithOrbitalAnimation();

      if (window.Logger) window.Logger.log('System interactions initialized');
    },

    // Initialize body selection for meeting creation
    initBodySelection() {
      const celestialBodies = document.querySelectorAll('.celestial-body');
      const selectionIndicator = document.getElementById('selection-indicator');
      const selectedBodiesInput = document.getElementById('selected-bodies-input');

      if (celestialBodies.length === 0) {
        if (window.Logger) window.Logger.info('No celestial bodies found for selection');
        return;
      }

      // Check if we're on a page with meeting creation
      if (!selectionIndicator && !selectedBodiesInput) {
        if (window.Logger) window.Logger.info('Not on meeting creation page, skipping body selection');
        return;
      }

      celestialBodies.forEach(body => {
        // Make bodies clickable for selection
        body.style.cursor = 'pointer';

        body.addEventListener('click', (e) => {
          e.stopPropagation();

          const bodyName = body.getAttribute('data-name');
          if (!bodyName) return;

          this.toggleBodySelection(body, bodyName);
          this.updateSelectionDisplay();
        });
      });

      if (window.Logger) window.Logger.log(`Initialized body selection for ${celestialBodies.length} bodies`);
    },

    // Toggle selection state of a celestial body
    toggleBodySelection(bodyElement, bodyName) {
      const index = this.selectedBodies.indexOf(bodyName);

      if (index > -1) {
        // Deselect
        this.selectedBodies.splice(index, 1);
        bodyElement.classList.remove('selected');
        bodyElement.setAttribute('stroke', bodyElement.dataset.originalStroke || 'none');
        bodyElement.setAttribute('stroke-width', bodyElement.dataset.originalStrokeWidth || '0');
      } else {
        // Check max selections
        if (this.maxSelections && this.selectedBodies.length >= this.maxSelections) {
          if (window.Logger) window.Logger.warn(`Maximum ${this.maxSelections} bodies can be selected`);
          return;
        }

        // Select
        this.selectedBodies.push(bodyName);
        bodyElement.classList.add('selected');

        // Store original stroke for deselection
        if (!bodyElement.dataset.originalStroke) {
          bodyElement.dataset.originalStroke = bodyElement.getAttribute('stroke') || 'none';
          bodyElement.dataset.originalStrokeWidth = bodyElement.getAttribute('stroke-width') || '0';
        }

        bodyElement.setAttribute('stroke', '#10b981');
        bodyElement.setAttribute('stroke-width', '4');
      }

      if (window.Logger) window.Logger.log(`Body ${bodyName} ${index > -1 ? 'deselected' : 'selected'}`);
    },

    // Update selection display
    updateSelectionDisplay() {
      const selectionIndicator = document.getElementById('selection-indicator');
      const selectedBodiesInput = document.getElementById('selected-bodies-input');

      if (selectionIndicator) {
        if (this.selectedBodies.length === 0) {
          selectionIndicator.innerHTML = '<em>Žádná tělesa nebyla vybrána</em>';
          selectionIndicator.style.color = '#94a3b8';
        } else {
          selectionIndicator.innerHTML = `
            <strong>Vybraná tělesa (${this.selectedBodies.length}):</strong><br>
            ${this.selectedBodies.join(', ')}
          `;
          selectionIndicator.style.color = '#10b981';
        }
      }

      // Update hidden input for form submission
      if (selectedBodiesInput) {
        selectedBodiesInput.value = JSON.stringify(this.selectedBodies);
      }
    },

    // Initialize enhanced tooltips with time dilation and orbital info
    initEnhancedTooltips() {
      const celestialBodies = document.querySelectorAll('.celestial-body');
      const tooltip = document.getElementById('tooltip');

      if (!tooltip || celestialBodies.length === 0) {
        return;
      }

      // Enhance existing tooltips with orbital information
      celestialBodies.forEach(body => {
        // Store original mouseover handler
        const originalMouseover = body.onmouseover;

        body.addEventListener('mouseover', (e) => {
          // Let the original handler from system_map.js run first
          if (originalMouseover) {
            originalMouseover.call(body, e);
          }

          // Add orbital information if available
          const orbitRadius = body.getAttribute('data-orbit-radius');
          const orbitalPeriod = body.getAttribute('data-orbital-period');
          const parent = body.getAttribute('data-parent');

          if (orbitRadius && orbitalPeriod && parent) {
            const orbitRadiusFormatted = parseFloat(orbitRadius).toExponential(2);
            const orbitalPeriodFormatted = parseFloat(orbitalPeriod).toFixed(2);

            // Append orbital info to existing tooltip
            const currentContent = tooltip.innerHTML;
            tooltip.innerHTML = currentContent + `
              <hr style="margin: 0.5rem 0; border-color: rgba(255,255,255,0.3);">
              <strong>Orbitální data:</strong><br>
              Rodič: ${parent}<br>
              Poloměr orbity: ${orbitRadiusFormatted} m<br>
              Orbitální perioda: ${orbitalPeriodFormatted} s
            `;
          }
        });
      });

      if (window.Logger) window.Logger.log('Enhanced tooltips with orbital information');
    },

    // Initialize orbital animation for celestial bodies
    initOrbitalAnimation() {
      const celestialBodies = document.querySelectorAll('.celestial-body');

      if (celestialBodies.length === 0) {
        if (window.Logger) window.Logger.info('No celestial bodies found for orbital animation');
        return;
      }

      // Check if OrbitalAnimator class already exists and is active
      // If it does, don't duplicate the animation
      if (typeof window.OrbitalAnimator !== 'undefined') {
        if (window.Logger) window.Logger.info('OrbitalAnimator class exists, skipping duplicate animation');
        return;
      }

      // Parse body data for animation
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

        // Pre-cache text element reference
        const textElement = element.nextElementSibling;
        const hasTextLabel = textElement && textElement.tagName === 'text';
        const radius = parseFloat(element.getAttribute('r')) || 5;

        // Calculate angular velocity
        const angularVelocity = orbitalPeriod > 0 ? (2 * Math.PI) / orbitalPeriod : 0;

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
          currentY: originalY
        };
      });

      // Create lookup map for finding bodies by name
      this.bodies.forEach(body => {
        if (body.name) {
          this.bodyLookup[body.name] = body;
        }
      });

      // Sort bodies by type to ensure parents are processed before children
      const typeOrder = { 'star': 0, 'planet': 1, 'moon': 2 };
      this.bodies.sort((a, b) => {
        const orderA = typeOrder[a.type] !== undefined ? typeOrder[a.type] : 999;
        const orderB = typeOrder[b.type] !== undefined ? typeOrder[b.type] : 999;
        return orderA - orderB;
      });

      // Start animation automatically
      this.startOrbitalAnimation();

      if (window.Logger) window.Logger.log(`Initialized orbital animation for ${this.bodies.length} bodies`);
    },

    // Start orbital animation
    startOrbitalAnimation() {
      if (this.animationActive) return;

      this.animationActive = true;
      this.animationStartTime = performance.now();
      this.animateOrbits();

      if (window.Logger) window.Logger.log('Orbital animation started');
    },

    // Stop orbital animation
    stopOrbitalAnimation() {
      if (!this.animationActive) return;

      this.animationActive = false;
      if (this.animationId) {
        cancelAnimationFrame(this.animationId);
        this.animationId = null;
      }

      if (window.Logger) window.Logger.log('Orbital animation stopped');
    },

    // Animate orbital motion (main animation loop)
    animateOrbits() {
      if (!this.animationActive) return;

      const currentTime = performance.now();
      const elapsedTime = (currentTime - this.animationStartTime) / 1000; // Convert to seconds

      // Update positions for all orbiting bodies
      for (let i = 0; i < this.bodies.length; i++) {
        const body = this.bodies[i];

        if (!body.hasOrbit) {
          // Non-orbiting body (e.g., star) - keep at original position
          body.currentX = body.originalX;
          body.currentY = body.originalY;
          continue;
        }

        // Calculate current angle based on orbital period and elapsed time
        const currentAngle = body.initialAngle + (body.angularVelocity * elapsedTime);

        // Get parent's current position (for moons orbiting moving planets)
        let parentX = body.parentX;
        let parentY = body.parentY;

        if (body.parentName && this.bodyLookup[body.parentName]) {
          const parentBody = this.bodyLookup[body.parentName];
          parentX = parentBody.currentX;
          parentY = parentBody.currentY;
        }

        // Calculate new position on circular orbit
        const newX = parentX + body.orbitRadius * Math.cos(currentAngle);
        const newY = parentY + body.orbitRadius * Math.sin(currentAngle);

        // Store current position for children to reference
        body.currentX = newX;
        body.currentY = newY;

        // Update SVG element position
        body.element.setAttribute('cx', newX.toFixed(2));
        body.element.setAttribute('cy', newY.toFixed(2));

        // Update text label position if exists
        if (body.textElement) {
          body.textElement.setAttribute('x', (newX + body.radius + 5).toFixed(2));
          body.textElement.setAttribute('y', (newY - body.radius - 5).toFixed(2));
        }
      }

      // Continue animation loop
      this.animationId = requestAnimationFrame(() => this.animateOrbits());
    },

    // Sync with orbital animation if it exists
    syncWithOrbitalAnimation() {
      // Check if OrbitalAnimator exists (from orbital_animation.js)
      if (typeof window.OrbitalAnimator === 'undefined') {
        if (window.Logger) window.Logger.info('OrbitalAnimator not found, skipping sync');
        return;
      }

      // Add hooks to highlight selected bodies during animation
      const celestialBodies = document.querySelectorAll('.celestial-body.selected');

      celestialBodies.forEach(body => {
        // Ensure selected bodies remain highlighted during animation
        body.style.strokeDasharray = 'none';
      });

      if (window.Logger) window.Logger.log('Synced with orbital animator');
    },

    // Clear all selections
    clearSelections() {
      const celestialBodies = document.querySelectorAll('.celestial-body.selected');

      celestialBodies.forEach(body => {
        const bodyName = body.getAttribute('data-name');
        this.toggleBodySelection(body, bodyName);
      });

      this.selectedBodies = [];
      this.updateSelectionDisplay();

      if (window.Logger) window.Logger.log('Cleared all selections');
    },

    // Get selected bodies
    getSelectedBodies() {
      return this.selectedBodies;
    }
  };

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => SystemInteractions.init());
  } else {
    SystemInteractions.init();
  }

  // Re-initialize on Turbo navigation if available
  if (typeof Turbo !== 'undefined') {
    document.addEventListener('turbo:load', () => SystemInteractions.init());
  }

  // Export for external access
  window.SystemInteractions = SystemInteractions;
})();
