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
      this.initSystemDilations();
      this.initSpaceClock();
      this.initPositionSelector();

      if (window.Logger) window.Logger.log('Galaxy interactions initialized');
    },

    // Markers of the LIVE galaxy map. The new-system position picker embeds
    // the same SVG, but there the systems must stay at their STORED positions
    // (the ones validation checks against) and must not navigate away or
    // pop tooltips — so markers inside #position-preview are excluded.
    liveMarkers() {
      return Array.from(document.querySelectorAll('#solar-systems .system-marker'))
        .filter(marker => !marker.closest('#position-preview'));
    },

    // Initialize click navigation on system markers
    initSystemNavigation() {
      const systemMarkers = this.liveMarkers();

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
      const markers = this.liveMarkers();
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

      function positionMarkers() {
        const epochSeconds = Date.now() / 1000;

        orbiting.forEach(m => {
          // A hovered marker is frozen in place so it cannot slide out from
          // under the cursor (it catches up to real time on mouseleave)
          if (m.marker.__orbitFrozen) return;

          const angle = m.initialAngle + (2 * Math.PI * epochSeconds) / m.orbitalPeriod;
          const x = CENTER_X + m.orbitRadius * Math.cos(angle);
          const y = CENTER_Y + m.orbitRadius * Math.sin(angle);
          m.marker.setAttribute('transform', `translate(${x.toFixed(2)}, ${y.toFixed(2)})`);
        });
      }

      function tick() {
        positionMarkers();
        requestAnimationFrame(tick);
      }

      // Position immediately (synchronously) — the SVG is rendered with the
      // stored positions, and waiting for the first animation frame would
      // make every marker visibly jump right after load.
      positionMarkers();
      requestAnimationFrame(tick);
      if (window.Logger) window.Logger.log(`Galaxy orbit animation running for ${orbiting.length} systems`);
    },

    // Tag each map marker with its black-hole time dilation for the hover
    // tooltip. Computed by RelativisticCalculator on the server and passed in
    // data-system-dilations (keyed by file id), so no physics is re-derived here.
    initSystemDilations() {
      const hero = document.querySelector('.galaxy-hero[data-system-dilations]');
      if (!hero) return;

      let dilations = {};
      try {
        dilations = JSON.parse(hero.getAttribute('data-system-dilations')) || {};
      } catch (e) {
        if (window.Logger) window.Logger.warn('Invalid data-system-dilations JSON');
        return;
      }

      this.liveMarkers().forEach(marker => {
        const dilation = dilations[marker.getAttribute('data-system-id')];
        if (typeof dilation === 'number' && dilation > 0) {
          marker.setAttribute('data-dilation', dilation);
        }
      });
    },

    // Xentorský orbitální čas: each rune digit is one solar system's orbital
    // phase around the black hole, quantized into 12 sectors (base-12, zero
    // at galactic north, increasing clockwise). Outermost system = leftmost
    // digit, so the rightmost digit ticks fastest. It reads as a SPACE
    // coordinate, but since orbits derive from wall-clock time it doubles
    // as a synchronized clock. A missing system leaves a "–" digit.
    initSpaceClock() {
      const clock = document.getElementById('space-clock');
      if (!clock) return;

      const RUNES = ['ᚠ', 'ᚢ', 'ᚦ', 'ᚨ', 'ᚱ', 'ᚲ', 'ᚷ', 'ᚹ', 'ᚺ', 'ᚾ', 'ᛁ', 'ᛃ'];
      const digits = clock.querySelectorAll('.space-clock-digit');
      const TAU = 2 * Math.PI;

      // Up to 4 systems ordered by orbital radius, outermost first
      // (ties broken by name for determinism)
      const systems = this.liveMarkers()
        .map(m => ({
          name: m.getAttribute('data-system-name') || '',
          orbitRadius: parseFloat(m.getAttribute('data-orbit-radius')) || 0,
          initialAngle: parseFloat(m.getAttribute('data-initial-angle')) || 0,
          orbitalPeriod: parseFloat(m.getAttribute('data-orbital-period')) || 0
        }))
        .filter(s => s.orbitRadius > 1 && s.orbitalPeriod > 0)
        .sort((a, b) => (b.orbitRadius - a.orbitRadius) || a.name.localeCompare(b.name))
        .slice(0, digits.length);

      function update() {
        const epochSeconds = Date.now() / 1000;

        digits.forEach((el, slot) => {
          const sys = systems[slot];
          if (!sys) {
            el.textContent = '–';
            el.removeAttribute('data-system');
            return;
          }

          // Same wall-clock formula as the orbit animation; +π/2 puts
          // sector zero at 12 o'clock (SVG y axis points down)
          const angle = sys.initialAngle + (TAU * epochSeconds) / sys.orbitalPeriod;
          const phase = (((angle + Math.PI / 2) % TAU) + TAU) % TAU;
          el.textContent = RUNES[Math.floor(phase / (TAU / 12)) % 12];
          el.setAttribute('data-system', sys.name);
        });
      }

      if (this.spaceClockTimer) clearInterval(this.spaceClockTimer);
      update();
      this.spaceClockTimer = setInterval(update, 1000);

      if (window.Logger) window.Logger.log(`Space clock running with ${systems.length}/${digits.length} systems`);
    },

    // Initialize tooltips for system markers
    initSystemTooltips() {
      const tooltip = document.getElementById('tooltip');
      const systemMarkers = this.liveMarkers();

      if (!tooltip) {
        if (window.Logger) window.Logger.info('Tooltip element not found');
        return;
      }

      if (systemMarkers.length === 0) {
        return;
      }

      // Hover: highlight + tooltip like in the system view, PLUS the hovered
      // marker's orbit freezes so it cannot escape from under the cursor.
      // mouseenter/mouseleave (not mouseover/mouseout) so transitions between
      // the group's children never blink the tooltip.
      systemMarkers.forEach(marker => {
        // Hover highlight itself is CSS (the map SVG's own style block)
        let lastPointer = null;

        marker.addEventListener('mouseenter', (e) => {
          marker.__orbitFrozen = true;
          lastPointer = { x: e.clientX, y: e.clientY };

          // First hover = the visitor found the markers; stop the "click me" pulse
          const hero = marker.closest('.galaxy-hero');
          if (hero) hero.classList.add('explored');

          const systemName = marker.getAttribute('data-system-name') || 'Neznámá soustava';
          const bodyCount = marker.getAttribute('data-body-count') || '0';
          const systemColor = marker.getAttribute('data-system-color') || '#7c8a9c';
          const binary = marker.getAttribute('data-binary') === 'true';
          const orbitRadius = parseFloat(marker.getAttribute('data-orbit-radius')) || 0;
          const dilation = parseFloat(marker.getAttribute('data-dilation'));

          // One of your hours, measured on this system's clock
          let dilationRow = '';
          if (dilation > 0) {
            const localSeconds = Math.round(3600 * dilation);
            dilationRow = `<div class="tooltip-row"><span>Za vaši 1 hodinu uběhne zde</span><span>${Math.floor(localSeconds / 60)} min ${localSeconds % 60} s</span></div>`;
          }

          tooltip.innerHTML = `
            <div class="tooltip-title"><span class="tooltip-dot" style="background: ${systemColor}"></span>${systemName}</div>
            ${binary ? '<div class="tooltip-row"><span>Hvězdy</span><span>dvojhvězda</span></div>' : ''}
            <div class="tooltip-row"><span>Počet těles</span><span>${bodyCount}</span></div>
            <div class="tooltip-row"><span>Vzdálenost od černé díry</span><span>${Math.round(orbitRadius * 1000).toLocaleString('cs-CZ')} km</span></div>
            ${dilationRow}
            <div class="tooltip-hint">Klikněte pro detail soustavy</div>
          `;

          tooltip.style.display = 'block';
          this.positionTooltip(e, tooltip);
        });

        marker.addEventListener('mousemove', (e) => {
          lastPointer = { x: e.clientX, y: e.clientY };
          this.positionTooltip(e, tooltip);
        });

        marker.addEventListener('mouseleave', (e) => {
          // The browser re-evaluates hover while OTHER markers animate and can
          // emit a spurious leave although the pointer is still on this
          // marker — ignore those, only honour a genuine exit.
          const px = e.clientX || (lastPointer && lastPointer.x);
          const py = e.clientY || (lastPointer && lastPointer.y);
          if (px != null && py != null) {
            const under = document.elementFromPoint(px, py);
            if (under && marker.contains(under)) return;
          }

          marker.__orbitFrozen = false;
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
          error: `Pozice je příliš blízko černé díry (vzdálenost: ${Math.round(distance * 1000).toLocaleString('cs-CZ')} km, minimum: ${(MIN_DISTANCE_FROM_BLACK_HOLE * 1000).toLocaleString('cs-CZ')} km)`
        };
      }

      // Warning for positions outside recommended range (but still allow)
      if (x < RECOMMENDED_MIN || x > RECOMMENDED_MAX || y < RECOMMENDED_MIN || y > RECOMMENDED_MAX) {
        if (window.Logger) window.Logger.warn('Position outside recommended range but still valid');
      }

      // Same spacing rule the server enforces, checked against the other
      // systems' STORED positions (data-x/data-y on the picker's markers)
      const MIN_DISTANCE_BETWEEN_SYSTEMS = 40;
      const others = document.querySelectorAll('#position-preview .system-marker');
      for (const marker of others) {
        const ox = parseFloat(marker.getAttribute('data-x'));
        const oy = parseFloat(marker.getAttribute('data-y'));
        if (isNaN(ox) || isNaN(oy)) continue;

        if (Math.hypot(x - ox, y - oy) < MIN_DISTANCE_BETWEEN_SYSTEMS) {
          const name = marker.getAttribute('data-system-name') || 'jiné soustavy';
          return {
            valid: false,
            error: `Pozice je příliš blízko soustavy ${name} (minimum: ${(MIN_DISTANCE_BETWEEN_SYSTEMS * 1000).toLocaleString('cs-CZ')} km)`
          };
        }
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
