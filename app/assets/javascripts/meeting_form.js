// Meeting Form Real-time Validation
// Provides instant feedback and validation for meeting forms

document.addEventListener('DOMContentLoaded', function() {
  // Find form elements
  const startTimeField = document.querySelector('input[name="start_time"], input[name="meeting[start_time]"]');
  const endTimeField = document.querySelector('input[name="end_time"], input[name="meeting[end_time]"]');
  const participantCheckboxes = document.querySelectorAll('input[name="participants[]"], input[name="meeting[participants][]"]');
  const submitButton = document.querySelector('input[type="submit"]');

  if (!startTimeField || !endTimeField || !submitButton) {
    if (window.Logger) window.Logger.warn('Meeting form elements not found');
    return;
  }

  // Time format regex: HH:MM (supports 0:00 to 23:59)
  const timeRegex = /^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/;

  // Error message containers
  let startTimeError = document.getElementById('start-time-error');
  let endTimeError = document.getElementById('end-time-error');
  let participantsError = document.getElementById('participants-error');
  let durationDisplay = document.getElementById('duration-display');

  // Validate time format
  function validateTimeFormat(timeString) {
    return timeRegex.test(timeString);
  }

  // Parse time string to minutes since midnight
  function parseTimeToMinutes(timeString) {
    if (!validateTimeFormat(timeString)) return null;
    const parts = timeString.split(':');
    const hours = parseInt(parts[0], 10);
    const minutes = parseInt(parts[1], 10);
    return hours * 60 + minutes;
  }

  // Calculate duration between start and end times (handles midnight wraparound)
  function calculateDuration(startTime, endTime) {
    const startMinutes = parseTimeToMinutes(startTime);
    const endMinutes = parseTimeToMinutes(endTime);

    if (startMinutes === null || endMinutes === null) return null;

    let duration = endMinutes - startMinutes;
    // Handle midnight wraparound
    if (duration < 0) {
      duration += 24 * 60;
    }

    return duration;
  }

  // Format duration as "X h Y min"
  function formatDuration(minutes) {
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;

    if (hours === 0) {
      return `${mins} min`;
    } else if (mins === 0) {
      return `${hours} h`;
    } else {
      return `${hours} h ${mins} min`;
    }
  }

  // Errors only speak up for fields the visitor has already been in (or
  // after a submit attempt); an untouched new form stays quiet
  const touched = new Set();
  let submitAttempted = false;
  const shouldShow = (key) => submitAttempted || touched.has(key);

  // Show error message
  function showError(errorElement, message) {
    const key = errorElement === startTimeError ? 'start' : errorElement === endTimeError ? 'end' : 'participants';
    if (!shouldShow(key)) {
      hideError(errorElement);
      return;
    }
    if (errorElement) {
      errorElement.textContent = message;
      errorElement.style.display = 'block';
    }
  }

  // Hide error message
  function hideError(errorElement) {
    if (errorElement) {
      errorElement.textContent = '';
      errorElement.style.display = 'none';
    }
  }

  // Validate start time
  function validateStartTime() {
    const value = startTimeField.value.trim();

    if (value === '') {
      showError(startTimeError, 'Začátek je povinný');
      return false;
    }

    if (!validateTimeFormat(value)) {
      showError(startTimeError, 'Formát musí být HH:MM (např. 12:00)');
      return false;
    }

    hideError(startTimeError);
    return true;
  }

  // Validate end time
  function validateEndTime() {
    const value = endTimeField.value.trim();

    if (value === '') {
      showError(endTimeError, 'Konec je povinný');
      return false;
    }

    if (!validateTimeFormat(value)) {
      showError(endTimeError, 'Formát musí být HH:MM (např. 13:30)');
      return false;
    }

    // Check if end time is after start time
    const startValue = startTimeField.value.trim();
    if (validateTimeFormat(startValue)) {
      const duration = calculateDuration(startValue, value);
      if (duration === 0) {
        showError(endTimeError, 'Konec musí být po začátku');
        return false;
      }
    }

    hideError(endTimeError);
    return true;
  }

  // Validate participants
  function validateParticipants() {
    const checkedCount = Array.from(participantCheckboxes).filter(cb => cb.checked).length;

    if (checkedCount < 2) {
      showError(participantsError, 'Vyberte aspoň dva účastníky');
      return false;
    }

    hideError(participantsError);
    return true;
  }

  // Update duration display
  function updateDuration() {
    const startValue = startTimeField.value.trim();
    const endValue = endTimeField.value.trim();

    if (validateTimeFormat(startValue) && validateTimeFormat(endValue)) {
      const duration = calculateDuration(startValue, endValue);
      if (duration !== null && duration > 0 && durationDisplay) {
        durationDisplay.textContent = `Délka: ${formatDuration(duration)}`;
        durationDisplay.style.display = 'block';
      } else if (durationDisplay) {
        durationDisplay.style.display = 'none';
      }
    } else if (durationDisplay) {
      durationDisplay.style.display = 'none';
    }
  }

  // Validate entire form
  function validateForm() {
    const startValid = validateStartTime();
    const endValid = validateEndTime();
    const participantsValid = validateParticipants();

    return startValid && endValid && participantsValid;
  }

  // Add event listeners
  startTimeField.addEventListener('input', function() {
    touched.add('start');
    validateStartTime();
    validateEndTime(); // Re-validate end time when start changes
    updateDuration();
    validateForm();
  });

  startTimeField.addEventListener('blur', function() {
    touched.add('start');
    validateStartTime();
    validateForm();
  });

  endTimeField.addEventListener('input', function() {
    touched.add('end');
    validateEndTime();
    updateDuration();
    validateForm();
  });

  endTimeField.addEventListener('blur', function() {
    touched.add('end');
    validateEndTime();
    validateForm();
  });

  participantCheckboxes.forEach(function(checkbox) {
    checkbox.addEventListener('change', function() {
      touched.add('participants');
      validateParticipants();
      validateForm();
    });
  });

  // Submitting reveals every problem at once and stays on the page if any
  const form = startTimeField.form;
  if (form) {
    form.addEventListener('submit', function(event) {
      submitAttempted = true;
      if (!validateForm()) {
        event.preventDefault();
        const firstError = form.querySelector('.error-message[style*="block"]');
        if (firstError) firstError.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    });
  }

  // Initial pass: shows the duration for prefilled times, no errors yet
  updateDuration();
  validateForm();

  if (window.Logger) window.Logger.log('Meeting form validation initialized');
});
