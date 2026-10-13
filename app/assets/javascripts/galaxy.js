// Galaxy Map Interactive Features
// Handles interactions with the galaxy visualization including system navigation,
// tooltips, and position selection for new systems

(function() {
  'use strict';

  // Galaxy interaction manager
  const GalaxyInteractions = {
    // Initialize all galaxy interactions
    init() {
      this.initSystemPanel();
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
    // On the tilted landing map, systems behind the black hole live in #systems-back.
    liveMarkers() {
      return Array.from(document.querySelectorAll('#solar-systems .system-marker, #systems-back .system-marker'))
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
        // Reachable from the keyboard too (Enter/Space = click)
        marker.setAttribute('tabindex', '0');
        marker.setAttribute('role', 'button');
        marker.setAttribute('aria-label', marker.getAttribute('data-system-name') || 'Soustava');
        marker.addEventListener('keydown', (e) => {
          if (e.key !== 'Enter' && e.key !== ' ') return;
          e.preventDefault();
          marker.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        });

        marker.addEventListener('click', (e) => {
          const systemId = marker.getAttribute('data-system-id');

          if (!systemId) {
            if (window.Logger) window.Logger.warn('System marker missing data-system-id');
            return;
          }

          // Landing: the profile slides in next to the map, a second click
          // on the same system slides it away; elsewhere (or a system
          // without a profile yet) open the system page
          if (marker.classList.contains('is-selected')) {
            this.closePanel();
            return;
          }
          if (!this.openPanel(systemId)) window.location.href = `/galaxy/systems/${systemId}`;
        });
      });

      if (window.Logger) window.Logger.log(`Initialized navigation for ${systemMarkers.length} system markers`);
    },

    // Real-time orbit animation: systems revolve around the black hole.
    // Positions derive from wall-clock time, so a refresh continues the
    // motion instead of resetting it. On the landing map the galaxy plane is
    // seen at an angle (see tiltScene); the motion itself is unchanged.
    initGalaxyOrbits() {
      const markers = this.liveMarkers();
      if (markers.length === 0) return;

      const CENTER_X = 400;
      const CENTER_Y = 400;
      const svg = document.querySelector('.galaxy-hero svg');
      const tilted = !!svg && markers.every(marker => svg.contains(marker));
      const project = tilted ? this.perspective(CENTER_X, CENTER_Y) : (x, y) => ({ x: x, y: y, s: 1 });
      const squash = tilted ? project.squash : 1;
      if (tilted) this.tiltScene(svg, project, markers);
      const backLayer = tilted ? svg.querySelector('#systems-back') : null;
      const frontLayer = tilted ? svg.querySelector('#solar-systems') : null;

      const orbiting = markers.map(marker => ({
        marker: marker,
        color: marker.getAttribute('data-system-color') || '#7c8a9c',
        orbitRadius: parseFloat(marker.getAttribute('data-orbit-radius')) || 0,
        initialAngle: parseFloat(marker.getAttribute('data-initial-angle')) || 0,
        orbitalPeriod: parseFloat(marker.getAttribute('data-orbital-period')) || 0,
        planets: tilted ? this.miniBodies(marker) : [],
        label: marker.querySelector('.system-label')
      })).filter(m => m.orbitRadius > 1 && m.orbitalPeriod > 0);

      if (orbiting.length === 0) return;

      function positionMarkers() {
        const epochSeconds = Date.now() / 1000;

        orbiting.forEach(m => {
          // Miniature planets keep circling even while the system is frozen
          m.planets.forEach(p => {
            const a = p.angle + (2 * Math.PI * epochSeconds) / p.period;
            p.x = p.ring * Math.cos(a);
            p.y = p.ring * Math.sin(a) * squash;
            p.el.setAttribute('cx', p.x.toFixed(2));
            p.el.setAttribute('cy', p.y.toFixed(2));
          });

          // A hovered marker is frozen in place so it cannot slide out from
          // under the cursor (it catches up to real time on mouseleave)
          if (m.marker.__orbitFrozen) return;

          const angle = m.initialAngle + (2 * Math.PI * epochSeconds) / m.orbitalPeriod;
          const p = project(CENTER_X + m.orbitRadius * Math.cos(angle), CENTER_Y + m.orbitRadius * Math.sin(angle));
          m.screen = p;
          m.marker.setAttribute('transform', `translate(${p.x.toFixed(2)}, ${p.y.toFixed(2)})` +
            (tilted ? ` scale(${p.s.toFixed(3)})` : ''));

          // Systems on the far side of the black hole pass behind it; the
          // label sits on the side away from the hole so it never crosses it
          if (backLayer) {
            const far = Math.sin(angle) < 0;
            if (m.far !== far) {
              m.far = far;
              (far ? backLayer : frontLayer).appendChild(m.marker);
              if (m.label) {
                if (m.labelY == null) m.labelY = parseFloat(m.label.getAttribute('y')) || -20;
                m.label.setAttribute('y', far ? m.labelY : -m.labelY + 9);
              }
            }
          }
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
      if (tilted) this.initSignals(svg, orbiting);
      if (window.Logger) window.Logger.log(`Galaxy orbit animation running for ${orbiting.length} systems`);
    },

    // Perspective camera for the landing map: the galaxy plane tilted away
    // from the viewer, nearer (lower) parts drawn larger. Returns a function
    // mapping flat map coordinates to { x, y, s } (s = scale at that depth).
    perspective(centerX, centerY) {
      const TILT = 62 * Math.PI / 180; // 0 = straight from above
      const CAMERA = 1500; // camera distance in map units
      const cos = Math.cos(TILT);
      const sin = Math.sin(TILT);

      const project = (x, y) => {
        const dx = x - centerX;
        const dy = y - centerY;
        const s = CAMERA / (CAMERA - dy * sin);
        return { x: centerX + dx * s, y: centerY + dy * cos * s, s: s };
      };
      project.squash = cos;
      return project;
    },

    // Rebuilds the flat map as a tilted scene: orbits become perspective
    // ellipses, the black hole gets an accretion ring that passes in front
    // of it, systems behind the hole get their own layer, and the viewBox is
    // cropped to the (now wide and short) galaxy.
    tiltScene(svg, project, markers) {
      const svgNS = 'http://www.w3.org/2000/svg';
      const ellipsePath = (cx, cy, r, steps) => {
        let d = '';
        for (let i = 0; i <= steps; i++) {
          const a = (i / steps) * 2 * Math.PI;
          const p = project(cx + r * Math.cos(a), cy + r * Math.sin(a));
          d += `${i ? 'L' : 'M'}${p.x.toFixed(1)},${p.y.toFixed(1)}`;
        }
        return d + 'Z';
      };

      svg.closest('.galaxy-hero').classList.add('galaxy-tilted');

      // The page itself is the sky; the SVG's own square background would show as a box
      const background = svg.querySelector(':scope > rect');
      if (background) background.setAttribute('fill', 'none');

      let maxRadius = 0;
      svg.querySelectorAll('circle.orbit-path').forEach(circle => {
        const r = parseFloat(circle.getAttribute('r'));
        maxRadius = Math.max(maxRadius, r);
        const path = document.createElementNS(svgNS, 'path');
        ['stroke', 'stroke-width', 'stroke-dasharray', 'opacity', 'data-system-id'].forEach(name => {
          if (circle.hasAttribute(name)) path.setAttribute(name, circle.getAttribute(name));
        });
        path.setAttribute('fill', 'none');
        path.setAttribute('class', 'orbit-path');
        path.setAttribute('d', ellipsePath(parseFloat(circle.getAttribute('cx')), parseFloat(circle.getAttribute('cy')), r, 120));
        circle.replaceWith(path);
      });

      // Black hole: redrawn as seen at an angle (see drawBlackHole)
      const blackHole = svg.querySelector('#black-hole');
      const core = svg.querySelector('.black-hole-core');
      if (blackHole && core) this.drawBlackHole(svg, blackHole, core, project.squash);

      // Systems behind the black hole are drawn before it
      const front = svg.querySelector('#solar-systems');
      if (blackHole && front) {
        const back = document.createElementNS(svgNS, 'g');
        back.setAttribute('id', 'systems-back');
        blackHole.before(back);
      }

      // Miniature systems lie in the galaxy plane too
      markers.forEach(marker => {
        marker.querySelectorAll('.mini-ring').forEach(ring => ring.setAttribute('transform', `scale(1 ${project.squash.toFixed(3)})`));
      });

      // Crop to the projected galaxy plus room for the outermost markers
      const extent = (maxRadius || 350) + 45;
      const outline = [];
      for (let i = 0; i < 72; i++) {
        const a = (i / 72) * 2 * Math.PI;
        outline.push(project(400 + extent * Math.cos(a), 400 + extent * Math.sin(a)));
      }
      const minX = Math.min(...outline.map(p => p.x));
      const maxX = Math.max(...outline.map(p => p.x));
      const minY = Math.min(...outline.map(p => p.y)) - 30; // labels above the farthest systems
      const maxY = Math.max(...outline.map(p => p.y));
      svg.setAttribute('viewBox', `${minX.toFixed(0)} ${minY.toFixed(0)} ${(maxX - minX).toFixed(0)} ${(maxY - minY).toFixed(0)}`);
      svg.removeAttribute('width');
      svg.removeAttribute('height');
    },

    // The black hole as the tilted galaxy shows it, in the spirit of the
    // well-known lensed renderings: a pure black shadow, a thin photon ring,
    // an accretion disc in the galaxy plane whose near half crosses in front
    // of the shadow, and the disc's far side bent up over the top of the
    // shadow by the hole's gravity. The approaching (left) side is brighter.
    // Faint streaks drift around the disc (CSS, stops under reduced motion).
    // The server's flat drawing stays in the DOM, hidden (picker uses it).
    drawBlackHole(svg, blackHole, core, squash) {
      const cx = parseFloat(core.getAttribute('cx'));
      const cy = parseFloat(core.getAttribute('cy'));
      const SHADOW = 27;
      const DISC_IN = 31;
      const DISC_OUT = 80;
      const f = (n) => n.toFixed(2);
      const ellipse = (r) => `M${f(cx - r)},${f(cy)} a${f(r)},${f(r * squash)} 0 1 0 ${f(2 * r)},0 a${f(r)},${f(r * squash)} 0 1 0 ${f(-2 * r)},0Z`;
      const band = ellipse(DISC_OUT) + ellipse(DISC_IN);
      const streaks = [40, 50, 60, 70].map((r, i) =>
        `<ellipse class="bh-streak bh-streak--${i % 2 ? 'slow' : 'fast'}" cx="${cx}" cy="${cy}" rx="${r}" ry="${f(r * squash)}" />`).join('');
      const disc = `
        <path d="${band}" fill="url(#bh-disc)" fill-rule="evenodd" />
        <g class="bh-streaks">${streaks}</g>`;
      // Lensed far side: a thin arc hugging the top of the shadow, fading
      // towards the disc plane
      const arcBand = (inner, outer) =>
        `M${f(cx - outer)},${f(cy)} A${outer},${outer} 0 0 1 ${f(cx + outer)},${f(cy)} ` +
        `L${f(cx + inner)},${f(cy)} A${inner},${inner} 0 0 0 ${f(cx - inner)},${f(cy)}Z`;
      const squashAround = `translate(${cx} ${cy}) scale(1 ${f(squash)}) translate(${-cx} ${-cy})`;

      Array.from(blackHole.children).forEach(child => { child.style.display = 'none'; });

      const scene = document.createElementNS('http://www.w3.org/2000/svg', 'g');
      scene.setAttribute('class', 'bh-scene');
      scene.innerHTML = `
        <defs>
          <radialGradient id="bh-glow">
            <stop offset="0%" stop-color="#ffcf8a" stop-opacity="0.3" />
            <stop offset="45%" stop-color="#ff9a3c" stop-opacity="0.1" />
            <stop offset="100%" stop-color="#ff7a1a" stop-opacity="0" />
          </radialGradient>
          <linearGradient id="bh-disc" gradientUnits="userSpaceOnUse" x1="${cx - DISC_OUT}" y1="0" x2="${cx + DISC_OUT}" y2="0">
            <stop offset="0%" stop-color="#fff6e0" />
            <stop offset="30%" stop-color="#ffd27a" />
            <stop offset="65%" stop-color="#f08a2a" />
            <stop offset="100%" stop-color="#8a2c0c" />
          </linearGradient>
          <radialGradient id="bh-disc-fade" gradientUnits="userSpaceOnUse" cx="${cx}" cy="${cy}" r="${DISC_OUT}" gradientTransform="${squashAround}">
            <stop offset="${f(DISC_IN / DISC_OUT)}" stop-color="#fff" stop-opacity="1" />
            <stop offset="0.7" stop-color="#fff" stop-opacity="0.45" />
            <stop offset="1" stop-color="#fff" stop-opacity="0" />
          </radialGradient>
          <linearGradient id="bh-lens" gradientUnits="userSpaceOnUse" x1="${cx - DISC_IN}" y1="0" x2="${cx + DISC_IN}" y2="0">
            <stop offset="0%" stop-color="#fff3d6" />
            <stop offset="55%" stop-color="#ffc061" />
            <stop offset="100%" stop-color="#c2531a" />
          </linearGradient>
          <linearGradient id="bh-lens-fade" gradientUnits="userSpaceOnUse" x1="0" y1="${cy - SHADOW - 8}" x2="0" y2="${cy}">
            <stop offset="0%" stop-color="#fff" stop-opacity="0.95" />
            <stop offset="100%" stop-color="#fff" stop-opacity="0.1" />
          </linearGradient>
          <mask id="bh-disc-mask"><rect x="${cx - 200}" y="${cy - 200}" width="400" height="400" fill="url(#bh-disc-fade)" /></mask>
          <mask id="bh-lens-mask"><rect x="${cx - 200}" y="${cy - 200}" width="400" height="200" fill="url(#bh-lens-fade)" /></mask>
          <clipPath id="bh-clip-shadow"><circle cx="${cx}" cy="${cy}" r="${SHADOW + 1.5}" /></clipPath>
          <clipPath id="bh-clip-near"><rect x="${cx - 200}" y="${cy}" width="400" height="200" /></clipPath>
        </defs>
        <circle class="bh-glow" cx="${cx}" cy="${cy}" r="120" fill="url(#bh-glow)" />
        <g class="bh-disc" mask="url(#bh-disc-mask)">${disc}</g>
        <path class="bh-lens" d="${arcBand(SHADOW + 1, SHADOW + 8)}" fill="url(#bh-lens)" mask="url(#bh-lens-mask)" />
        <circle class="bh-shadow" cx="${cx}" cy="${cy}" r="${SHADOW}" />
        <circle class="bh-photon-ring" cx="${cx}" cy="${cy}" r="${SHADOW + 0.4}" />
        <circle class="bh-hit" cx="${cx}" cy="${cy}" r="${SHADOW + 8}" />
        <g clip-path="url(#bh-clip-shadow)"><g clip-path="url(#bh-clip-near)"><g mask="url(#bh-disc-mask)">${disc}</g></g></g>
      `;
      blackHole.appendChild(scene);

      // Its name moves from the (hidden) label to a hover title
      const name = core.getAttribute('data-name');
      if (name) {
        const title = document.createElementNS('http://www.w3.org/2000/svg', 'title');
        title.textContent = `Černá díra ${name}`;
        blackHole.prepend(title);
      }

      // The black hole has its own profile in the panel. Only the shadow
      // area takes clicks (CSS): the glow and disc must not cover systems
      // passing behind the hole.
      if (!this.profiles || !this.profiles.some(p => p.dataset.fileId === 'black-hole')) return;
      blackHole.classList.add('is-clickable');
      blackHole.setAttribute('tabindex', '0');
      blackHole.setAttribute('role', 'button');
      blackHole.setAttribute('aria-label', `Černá díra ${name || ''}`.trim());
      const toggle = () => {
        if (blackHole.classList.contains('is-selected')) this.closePanel();
        else this.openPanel('black-hole');
      };
      blackHole.addEventListener('click', toggle);
      blackHole.addEventListener('keydown', (e) => {
        if (e.key !== 'Enter' && e.key !== ' ') return;
        e.preventDefault();
        toggle();
      });
    },

    // The miniature bodies of a marker that carry orbit data (planets and
    // binary stars, see GalaxyVisualizer). On the tilted map JS moves them on
    // flattened orbits from the wall clock, so the CSS spin is switched off.
    // Markers from an older SVG without the data keep their CSS spin.
    miniBodies(marker) {
      const bodies = Array.from(marker.querySelectorAll('[data-ring]')).map(el => ({
        el: el,
        ring: parseFloat(el.getAttribute('data-ring')) || 0,
        angle: parseFloat(el.getAttribute('data-angle')) || 0,
        period: parseFloat(el.getAttribute('data-period')) || 0,
        planet: el.classList.contains('mini-planet'),
        x: 0,
        y: 0
      })).filter(b => b.ring > 0 && b.period > 0);

      if (bodies.length > 0) {
        marker.classList.add('js-orbits');
        marker.querySelectorAll('.mini-spin').forEach(g => g.removeAttribute('transform'));
      }
      return bodies;
    },

    // Decorative traffic on the galaxy map: mostly between systems, now and
    // then between two planets of one system. Purely visual, not tied to
    // meetings. Drawing is shared with the system page (runSignals).
    initSignals(svg, systems) {
      if (systems.length < 2) return;

      const pick = (list) => list[Math.floor(Math.random() * list.length)];
      const systemPoint = (m) => () => m.screen;
      const planetPoint = (m, p) => () => ({ x: m.screen.x + p.x * m.screen.s, y: m.screen.y + p.y * m.screen.s });

      this.runSignals(svg, () => {
        const placed = systems.filter(m => m.screen);
        if (placed.length < 2) return null;

        const local = placed.filter(m => m.planets.filter(p => p.planet).length >= 2);
        if (local.length && Math.random() < 0.25) {
          const m = pick(local);
          const planets = m.planets.filter(p => p.planet);
          const a = pick(planets);
          return { from: planetPoint(m, a), to: planetPoint(m, pick(planets.filter(p => p !== a))), color: m.color, scale: 0.5 };
        }
        const a = pick(placed);
        return { from: systemPoint(a), to: systemPoint(pick(placed.filter(m => m !== a))), color: a.color, scale: 1 };
      });
    },

    // Signals drawn as connections rather than projectiles:
    // - a message spins a thin thread from sender to receiver behind a soft
    //   glowing dot, the receiver answers with a gentle ripple, then the
    //   thread fades away;
    // - a call is an open line: a faint dotted arc flowing slowly while both
    //   ends breathe.
    // Arcs rise "above" the plane. pickPair() returns { from, to, color,
    // scale } (from/to are functions giving the current point) or null.
    runSignals(svg, pickPair) {
      if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

      const svgNS = 'http://www.w3.org/2000/svg';
      const layer = document.createElementNS(svgNS, 'g');
      layer.setAttribute('class', 'signals');
      layer.setAttribute('aria-hidden', 'true');
      svg.appendChild(layer);

      const MAX_SIGNALS = 4;
      const FADE_MS = 1100;
      const signals = [];
      let nextSpawn = performance.now() + 900;

      const make = (tag, attrs) => {
        const el = document.createElementNS(svgNS, tag);
        Object.keys(attrs).forEach(name => el.setAttribute(name, attrs[name]));
        layer.appendChild(el);
        return el;
      };
      const bezier = (a, c, b, t) => ({
        x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * c.x + t * t * b.x,
        y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * c.y + t * t * b.y
      });
      const ease = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
      // The thread is drawn by DISTANCE along the arc (dasharray with
      // pathLength=1), so the packet must sit at the same distance, not at
      // the same bezier parameter (those differ along a curve: the dot
      // would run ahead of or lag behind the thread).
      const pointAtFraction = (a, c, b, fraction) => {
        const STEPS = 32;
        const lengths = [0];
        let prev = a;
        for (let i = 1; i <= STEPS; i++) {
          const p = bezier(a, c, b, i / STEPS);
          lengths.push(lengths[i - 1] + Math.hypot(p.x - prev.x, p.y - prev.y));
          prev = p;
        }
        const target = fraction * lengths[STEPS];
        let i = 1;
        while (i < STEPS && lengths[i] < target) i++;
        const span = lengths[i] - lengths[i - 1] || 1;
        return bezier(a, c, b, (i - 1 + (target - lengths[i - 1]) / span) / STEPS);
      };
      const place = (el, p) => {
        el.setAttribute('cx', p.x.toFixed(1));
        el.setAttribute('cy', p.y.toFixed(1));
      };

      function spawn(now) {
        const pair = pickPair();
        if (!pair) return;
        const { from, to, color, scale } = pair;

        const call = Math.random() < 0.35;
        const distance = Math.hypot(to().x - from().x, to().y - from().y);
        const signal = {
          from: from,
          to: to,
          call: call,
          color: color,
          scale: scale,
          start: now,
          // A call holds the line open; a message travels at an unhurried pace
          duration: call ? 4500 + Math.random() * 2500 : 2200 + distance * 7,
          path: make('path', {
            class: call ? 'signal-thread signal-thread--call' : 'signal-thread',
            stroke: color,
            'stroke-width': ((call ? 1.2 : 1) * scale).toFixed(2),
            pathLength: '1',
            opacity: 0
          }),
          dots: call
            ? [make('circle', { class: 'signal-end', r: (3 * scale).toFixed(2), stroke: color, 'stroke-width': (0.8 * scale).toFixed(2) }),
               make('circle', { class: 'signal-end', r: (3 * scale).toFixed(2), stroke: color, 'stroke-width': (0.8 * scale).toFixed(2) })]
            : [make('circle', { class: 'signal-packet', r: (1.8 * scale).toFixed(2), fill: color })]
        };
        signals.push(signal);
      }

      function frame(now) {
        if (now >= nextSpawn) {
          if (signals.length < MAX_SIGNALS) spawn(now);
          nextSpawn = now + 900 + Math.random() * 1600;
        }

        for (let i = signals.length - 1; i >= 0; i--) {
          const s = signals[i];
          const elapsed = now - s.start;
          const a = s.from();
          const b = s.to();
          const lift = Math.hypot(b.x - a.x, b.y - a.y) * 0.25;
          const c = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - lift };
          s.path.setAttribute('d', `M${a.x.toFixed(1)},${a.y.toFixed(1)} Q${c.x.toFixed(1)},${c.y.toFixed(1)} ${b.x.toFixed(1)},${b.y.toFixed(1)}`);

          if (s.call) {
            const t = Math.min(elapsed / s.duration, 1);
            const presence = Math.min(1, Math.sin(Math.PI * t) * 2.5); // quick fade in/out, steady middle
            s.path.setAttribute('opacity', (0.4 * presence).toFixed(2));
            s.path.setAttribute('stroke-dashoffset', (-elapsed / 9000).toFixed(4));
            const breath = 1 + 0.35 * Math.sin(elapsed / 260);
            [a, b].forEach((p, k) => {
              place(s.dots[k], p);
              s.dots[k].setAttribute('r', (3 * s.scale * breath).toFixed(2));
              s.dots[k].setAttribute('opacity', (0.6 * presence).toFixed(2));
            });
            if (t >= 1) {
              s.path.remove();
              s.dots.forEach(d => d.remove());
              signals.splice(i, 1);
            }
            continue;
          }

          // Message: travel, then a ripple at the receiver while the thread fades
          const travel = Math.min(elapsed / s.duration, 1);
          const fade = Math.max(0, (elapsed - s.duration) / FADE_MS);
          const reach = ease(travel);
          s.path.setAttribute('stroke-dasharray', `${reach.toFixed(4)} 2`);
          s.path.setAttribute('opacity', (0.45 * Math.min(1, travel * 6) * (1 - fade)).toFixed(2));

          const packet = s.dots[0];
          if (travel < 1) {
            place(packet, pointAtFraction(a, c, b, reach));
          } else {
            // The packet becomes the ripple around the receiver
            place(packet, b);
            packet.setAttribute('class', 'signal-ripple');
            packet.setAttribute('fill', 'none');
            packet.setAttribute('stroke', s.color);
            packet.setAttribute('stroke-width', (0.8 * s.scale).toFixed(2));
            packet.setAttribute('r', ((2 + 9 * Math.min(fade, 1)) * s.scale).toFixed(2));
            packet.setAttribute('opacity', (0.6 * (1 - fade)).toFixed(2));
          }

          if (fade >= 1) {
            s.path.remove();
            packet.remove();
            signals.splice(i, 1);
          }
        }

        requestAnimationFrame(frame);
      }

      requestAnimationFrame(frame);
    },

    // The landing's system panel: every profile is server-rendered (hidden);
    // a click on a marker shows that system's profile next to the map and
    // keeps #soustava-<db id> in the URL so the choice survives a reload.
    initSystemPanel() {
      const panel = document.getElementById('system-panel');
      const stage = document.getElementById('galaxy-stage');
      if (!panel || !stage) return;

      this.panel = panel;
      this.stage = stage;
      this.profiles = Array.from(panel.querySelectorAll('.system-profile'));

      panel.querySelector('.system-panel-close').addEventListener('click', () => this.closePanel());
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && stage.classList.contains('has-selection')) this.closePanel();
      });

      const fromHash = this.profiles.find(p => '#' + p.dataset.hash === location.hash);
      if (fromHash) this.openPanel(fromHash.dataset.fileId, { fromHash: true });
    },

    // @return [Boolean] false when there is no panel/profile for the system
    openPanel(fileId, options = {}) {
      if (!this.panel) return false;
      const profile = this.profiles.find(p => p.dataset.fileId === fileId);
      if (!profile) return false;

      this.profiles.forEach(p => { p.hidden = p !== profile; });
      this.panel.hidden = false;
      this.stage.classList.add('has-selection');

      // Replay the slide-in for every newly chosen system
      profile.classList.remove('is-entering');
      void profile.offsetWidth;
      profile.classList.add('is-entering');
      this.panel.scrollTop = 0;

      this.liveMarkers().forEach(marker => {
        marker.classList.toggle('is-selected', marker.getAttribute('data-system-id') === fileId);
      });
      const blackHole = document.querySelector('.galaxy-hero #black-hole');
      if (blackHole) blackHole.classList.toggle('is-selected', fileId === 'black-hole');
      // The visitor found the systems; stop the "click me" pulse
      const hero = document.querySelector('.galaxy-hero');
      if (hero) hero.classList.add('explored');

      if (!options.fromHash) {
        history.replaceState(null, '', '#' + profile.dataset.hash);
        // Single-column layout: the panel sits under the map
        if (window.matchMedia('(max-width: 900px)').matches) {
          this.panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      }
      return true;
    },

    closePanel() {
      if (!this.panel) return;
      this.stage.classList.remove('has-selection');
      this.panel.hidden = true;
      this.liveMarkers().forEach(marker => marker.classList.remove('is-selected'));
      const blackHole = document.querySelector('.galaxy-hero #black-hole');
      if (blackHole) blackHole.classList.remove('is-selected');
      history.replaceState(null, '', location.pathname + location.search);
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
            <div class="tooltip-hint">Klikněte pro profil soustavy</div>
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
