// Relativistic Effects Visualization
// Handles expand/collapse and animations for meeting relativistic info

document.addEventListener('DOMContentLoaded', function() {
  initializeRelativistics();
});

// The whole meeting row opens/closes its relativistic detail row; the
// chevron button (rendered in _meeting) is the keyboard/screen-reader
// equivalent. Clicks on the edit link / delete form keep their own action.
function initializeRelativistics() {
  const meetingRows = document.querySelectorAll('tbody#meetings-table tr[id^="meeting_"]');

  meetingRows.forEach(function(row) {
    const toggleButton = row.querySelector('.relativistic-toggle');
    const detailsRow = document.getElementById('relativistic-' + row.id);
    if (!toggleButton || !detailsRow) return;

    function toggle() {
      const opening = detailsRow.style.display === 'none';

      detailsRow.style.display = opening ? 'table-row' : 'none';
      detailsRow.classList.toggle('open', opening);
      row.classList.toggle('expanded', opening);
      toggleButton.classList.toggle('active', opening);
      toggleButton.setAttribute('aria-expanded', String(opening));
      toggleButton.setAttribute('aria-label', opening ? 'Skrýt relativistické efekty' : 'Zobrazit relativistické efekty');

      if (opening) animateSignalPulses(detailsRow);
    }

    row.addEventListener('click', function(e) {
      const interactive = e.target.closest('a, button, form, input, select, textarea');
      if (interactive && interactive !== toggleButton) return;
      // Selecting text in the row should not toggle it
      if (window.getSelection && String(window.getSelection()).length > 0) return;

      e.preventDefault();
      toggle();
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
