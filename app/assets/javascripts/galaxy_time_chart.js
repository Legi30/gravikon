// "Čas napříč galaxií" chart in the landing story: every body's dilation
// vs. its system's distance from the black hole (data from
// DashboardHelper#galaxy_time_chart_data, HTML-escaped data-chart attribute).
document.addEventListener('DOMContentLoaded', function() {
  const canvas = document.getElementById('galaxyTimeChart');
  if (!canvas || !window.Chart) return;

  const data = JSON.parse(canvas.getAttribute('data-chart'));

  // Each system arrives with its shared colour (ApplicationHelper#system_color,
  // a validated categorical palette in fixed id order); systems past the
  // palette are flagged `other` and fold into one neutral "Ostatní" series.
  const SURFACE = '#000814'; // the landing page's deep-space background
  const TEXT = 'rgba(224, 224, 224, 0.85)';
  const MUTED = 'rgba(224, 224, 224, 0.55)';
  const RADIUS = { star: 6, planet: 4.5, moon: 3 };
  // Canvas units → km for display (1 unit = 1 000 km, PhysicsConstants::UNIT_METERS)
  const KM = (units) => Math.round(units * 1000).toLocaleString('cs-CZ');

  const toPoints = (system) => system.bodies.map(body => ({
    x: system.distance,
    y: body.dilation * 60,
    name: body.name,
    system: system.name,
    type: body.type
  }));

  const scatter = (label, color, points, systemLabel) => ({
    type: 'scatter',
    label: label,
    data: points,
    systemLabel: systemLabel,
    backgroundColor: color,
    borderColor: SURFACE,
    borderWidth: 1.5,
    pointRadius: points.map(p => RADIUS[p.type] || 4),
    pointHoverRadius: points.map(p => (RADIUS[p.type] || 4) + 2),
    pointHitRadius: 8
  });

  const named = data.systems.filter(system => !system.other);
  const rest = data.systems.filter(system => system.other);
  const datasets = named.map(system => scatter(system.name, system.color, toPoints(system), true));
  if (rest.length > 0) {
    datasets.push(scatter('Ostatní', rest[0].color, rest.flatMap(toPoints), false));
  }

  datasets.push({
    type: 'line',
    label: 'Jen černá díra',
    data: data.curve.map(p => ({ x: p.x, y: p.y * 60 })),
    borderColor: 'rgba(224, 224, 224, 0.45)',
    borderWidth: 2,
    borderDash: [5, 4],
    pointRadius: 0,
    pointHitRadius: 4,
    tension: 0.3,
    order: 10
  });

  // Direct labels (system name above its topmost body) while there are few
  // enough systems to label without collisions; text uses ink, not series colour
  const directLabels = {
    id: 'directLabels',
    afterDatasetsDraw(chart) {
      // Narrow charts squeeze neighbouring labels together; the legend covers it
      if (named.length > 4 || chart.width < 600) return;
      const ctx = chart.ctx;
      ctx.save();
      ctx.font = '600 12px Inter, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = TEXT;
      chart.data.datasets.forEach((dataset, i) => {
        const meta = chart.getDatasetMeta(i);
        if (!dataset.systemLabel || meta.hidden) return;
        const top = meta.data.reduce((best, el) => (!best || el.y < best.y ? el : best), null);
        if (top) ctx.fillText(dataset.label, top.x, top.y - 12);
      });
      ctx.restore();
    }
  };

  new Chart(canvas, {
    data: { datasets: datasets },
    plugins: [directLabels],
    options: {
      responsive: true,
      maintainAspectRatio: false,
      layout: { padding: { top: 18 } },
      scales: {
        x: {
          type: 'linear',
          // Systems can't sit closer than 50 units; the curve ends just past the farthest one
          min: 50,
          max: data.curve.length ? data.curve[data.curve.length - 1].x : undefined,
          title: { display: true, text: 'Vzdálenost od černé díry (km)', color: MUTED },
          ticks: { color: MUTED, callback: (value) => KM(value) },
          grid: { color: 'rgba(255, 255, 255, 0.05)' }
        },
        y: {
          suggestedMax: 60,
          title: { display: true, text: 'Minut za hodinu pozorovatele', color: MUTED },
          ticks: { color: MUTED },
          grid: { color: 'rgba(255, 255, 255, 0.06)' }
        }
      },
      plugins: {
        legend: {
          position: 'bottom',
          labels: { color: TEXT, usePointStyle: true, font: { family: 'Inter, sans-serif', size: 12 } }
        },
        tooltip: {
          backgroundColor: 'rgba(26, 30, 58, 0.95)',
          titleColor: '#ffd700',
          bodyColor: '#e0e0e0',
          borderColor: 'rgba(255, 215, 0, 0.5)',
          borderWidth: 1,
          callbacks: {
            title: (items) => {
              const raw = items[0].raw;
              return raw.name ? `${raw.name} (${raw.system})` : `Jen černá díra, ${KM(raw.x)} km`;
            },
            label: (item) => `${item.parsed.y.toFixed(1)} min za hodinu pozorovatele`
          }
        }
      }
    }
  });
});
