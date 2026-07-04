// System Map Interactive Features
// Adds hover effects and tooltips to celestial bodies in the SVG map

document.addEventListener('DOMContentLoaded', function() {
  // Get tooltip element
  const tooltip = document.getElementById('tooltip');
  if (!tooltip) {
    if (window.Logger) window.Logger.warn('Tooltip element not found');
    return;
  }

  // Select all celestial body circles
  const celestialBodies = document.querySelectorAll('.celestial-body');

  if (celestialBodies.length === 0) {
    if (window.Logger) window.Logger.warn('No celestial bodies found in SVG');
    return;
  }

  // Add event listeners to each body
  celestialBodies.forEach(function(body) {
    // Store original stroke properties
    const originalStroke = body.getAttribute('stroke') || 'none';
    const originalStrokeWidth = body.getAttribute('stroke-width') || '0';

    // Mouseover: highlight and show tooltip
    body.addEventListener('mouseover', function(event) {
      // Freeze this body's orbit so it cannot slide out from under the
      // cursor (orbital_animation.js skips frozen bodies; it catches up
      // to real time on mouseout)
      body.__orbitFrozen = true;

      // Highlight the body
      body.setAttribute('stroke', '#ffd700');
      body.setAttribute('stroke-width', '3');
      body.style.cursor = 'pointer';

      // Get body data
      const name = body.getAttribute('data-name') || 'Neznámé';
      const type = body.getAttribute('data-type') || 'Neznámé';
      const radius = body.getAttribute('data-radius') || '0';
      const mass = body.getAttribute('data-mass') || '0';
      const dilation = body.getAttribute('data-dilation') || '1.0';

      // Format values
      const radiusFormatted = parseFloat(radius).toExponential(2);
      const massFormatted = parseFloat(mass).toExponential(2);
      const dilationFormatted = parseFloat(dilation).toFixed(4);

      // Translate type to Czech
      let typeCzech = type;
      switch(type) {
        case 'star': typeCzech = 'Hvězda'; break;
        case 'planet': typeCzech = 'Planeta'; break;
        case 'moon': typeCzech = 'Měsíc'; break;
      }

      // Build tooltip content
      tooltip.innerHTML = `
        <div class="tooltip-title">${name}</div>
        <div class="tooltip-row"><span>Typ</span><span>${typeCzech}</span></div>
        <div class="tooltip-row"><span>Poloměr</span><span>${radiusFormatted} m</span></div>
        <div class="tooltip-row"><span>Hmotnost</span><span>${massFormatted} kg</span></div>
        <div class="tooltip-row"><span>Dilatace času</span><span>${dilationFormatted}×</span></div>
      `;

      // Show tooltip
      tooltip.style.display = 'block';
    });

    // Mousemove: position tooltip near cursor
    body.addEventListener('mousemove', function(event) {
      // Position tooltip slightly offset from cursor
      const offsetX = 15;
      const offsetY = 15;

      let x = event.clientX + offsetX;
      let y = event.clientY + offsetY;

      // Prevent tooltip from going off-screen
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
    });

    // Mouseout: remove highlight and hide tooltip
    body.addEventListener('mouseout', function(event) {
      // Ignore spurious outs emitted while other bodies animate — only
      // honour a genuine exit (pointer no longer over this body)
      if (event.clientX != null) {
        const under = document.elementFromPoint(event.clientX, event.clientY);
        if (under === body) return;
      }

      body.__orbitFrozen = false;

      // Restore original stroke
      body.setAttribute('stroke', originalStroke);
      body.setAttribute('stroke-width', originalStrokeWidth);
      body.style.cursor = 'default';

      // Hide tooltip
      tooltip.style.display = 'none';
    });
  });

  if (window.Logger) window.Logger.log(`Initialized interactive features for ${celestialBodies.length} celestial bodies`);
});
