// Relativistic Effects Visualization
// Handles expand/collapse and animations for meeting relativistic info

document.addEventListener('DOMContentLoaded', function() {
  // Add toggle buttons to meeting rows
  initializeRelativistics();

  // Handle dynamic content (Turbo Streams)
  document.addEventListener('turbo:load', initializeRelativistics);
});

function initializeRelativistics() {
  const meetingRows = document.querySelectorAll('tbody#meetings-table tr[id^="meeting_"]');

  meetingRows.forEach(function(row) {
    // Skip if already initialized
    if (row.querySelector('.relativistic-toggle')) {
      return;
    }

    const meetingId = row.id;

    // Create toggle button
    const toggleButton = document.createElement('button');
    toggleButton.textContent = '📊 Relativistika';
    toggleButton.className = 'button-like relativistic-toggle';
    toggleButton.style.marginLeft = '0.5rem';
    toggleButton.title = 'Zobrazit relativistické efekty';
    toggleButton.setAttribute('aria-label', 'Zobrazit relativistické efekty pro tuto schůzku');
    toggleButton.setAttribute('aria-expanded', 'false');
    toggleButton.setAttribute('aria-controls', 'relativistic-' + meetingId);
    toggleButton.type = 'button';

    // Add button to actions cell
    const actionsCell = row.querySelector('td:last-child > div');
    if (actionsCell) {
      actionsCell.appendChild(toggleButton);
    }

    // Toggle functionality
    toggleButton.addEventListener('click', function(e) {
      e.preventDefault();
      const detailsRow = document.getElementById('relativistic-' + meetingId);

      if (detailsRow) {
        if (detailsRow.style.display === 'none') {
          detailsRow.style.display = 'table-row';
          toggleButton.textContent = '📊 Skrýt';
          toggleButton.classList.add('active');
          toggleButton.setAttribute('aria-expanded', 'true');
          toggleButton.setAttribute('aria-label', 'Skrýt relativistické efekty');

          // Start animations
          animateSignalPulses(detailsRow);
        } else {
          detailsRow.style.display = 'none';
          toggleButton.textContent = '📊 Relativistika';
          toggleButton.classList.remove('active');
          toggleButton.setAttribute('aria-expanded', 'false');
          toggleButton.setAttribute('aria-label', 'Zobrazit relativistické efekty pro tuto schůzku');
        }
      }
    });
  });
}

function animateSignalPulses(detailsRow) {
  const pulses = detailsRow.querySelectorAll('.signal-pulse');

  pulses.forEach(function(pulse, index) {
    // Stagger animations
    pulse.style.animationDelay = (index * 0.5) + 's';
  });
}

// Add tooltips for time bars
document.addEventListener('mouseover', function(e) {
  if (e.target.classList.contains('time-bar')) {
    const duration = e.target.getAttribute('data-duration');
    const dilation = e.target.getAttribute('data-dilation');

    if (duration && dilation) {
      e.target.title = `Lokální čas: ${duration} min | Dilatace: ${dilation}×`;
    }
  }
});

if (window.Logger) window.Logger.log('Relativistic visualization initialized');
