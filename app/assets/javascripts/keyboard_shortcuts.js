// Keyboard Shortcuts System
// Provides keyboard navigation and accessibility features

class KeyboardShortcuts {
  constructor() {
    this.shortcuts = {
      'd': { action: () => this.navigate('/dashboard'), description: 'Otevřít Přehled' },
      's': { action: () => this.navigate('/meetings'), description: 'Otevřít seznam Schůzek' },
      'g': { action: () => this.navigate('/galaxy'), description: 'Otevřít mapu Galaxie' },
      'n': { action: () => this.navigate('/meetings/new'), description: 'Nová schůzka' },
      '?': { action: () => this.showHelp(), description: 'Zobrazit nápovědu klávesových zkratek' },
      'Escape': { action: () => this.hideHelp(), description: 'Zavřít nápovědu', hidden: true }
    };

    this.helpModalVisible = false;
    this.init();
  }

  init() {
    // Listen for keyboard events
    document.addEventListener('keydown', (e) => this.handleKeyPress(e));

    // Create help modal structure
    this.createHelpModal();

    if (window.Logger) window.Logger.log('Keyboard shortcuts initialized. Press ? for help.');
  }

  handleKeyPress(event) {
    // Ignore if user is typing in an input field
    const activeElement = document.activeElement;
    const isInputField = activeElement.tagName === 'INPUT' ||
                        activeElement.tagName === 'TEXTAREA' ||
                        activeElement.tagName === 'SELECT' ||
                        activeElement.isContentEditable;

    // Allow Escape key even in input fields to close modal
    if (event.key === 'Escape' && this.helpModalVisible) {
      event.preventDefault();
      this.hideHelp();
      return;
    }

    // Don't trigger shortcuts when typing in input fields
    if (isInputField && event.key !== 'Escape') {
      return;
    }

    // Check if the pressed key has a shortcut
    const shortcut = this.shortcuts[event.key];
    if (shortcut) {
      event.preventDefault();
      shortcut.action();
    }
  }

  navigate(url) {
    window.location.href = url;
  }

  showHelp() {
    const modal = document.getElementById('keyboard-shortcuts-modal');
    if (modal) {
      modal.style.display = 'flex';
      this.helpModalVisible = true;

      // Focus the modal for accessibility
      modal.focus();

      // Announce to screen readers
      this.announce('Nápověda klávesových zkratek otevřena');
    }
  }

  hideHelp() {
    const modal = document.getElementById('keyboard-shortcuts-modal');
    if (modal) {
      modal.style.display = 'none';
      this.helpModalVisible = false;

      // Announce to screen readers
      this.announce('Nápověda klávesových zkratek zavřena');
    }
  }

  createHelpModal() {
    // Create modal HTML
    const modalHTML = `
      <div id="keyboard-shortcuts-modal" class="modal" role="dialog" aria-labelledby="modal-title" aria-modal="true" tabindex="-1" style="display: none;">
        <div class="modal-overlay" aria-hidden="true"></div>
        <div class="modal-content">
          <div class="modal-header">
            <h2 id="modal-title">⌨️ Klávesové zkratky</h2>
            <button class="modal-close" aria-label="Zavřít nápovědu" onclick="window.keyboardShortcuts.hideHelp()">
              <span aria-hidden="true">×</span>
            </button>
          </div>
          <div class="modal-body">
            <p class="modal-description">Použijte tyto klávesové zkratky pro rychlejší navigaci v aplikaci:</p>
            <table class="shortcuts-table" role="table">
              <thead>
                <tr>
                  <th scope="col">Klávesa</th>
                  <th scope="col">Akce</th>
                </tr>
              </thead>
              <tbody>
                ${this.generateShortcutsTable()}
              </tbody>
            </table>
            <p class="modal-note">
              <small>Tip: Klávesové zkratky nefungují, když píšete do formulářových polí.</small>
            </p>
          </div>
          <div class="modal-footer">
            <button class="btn btn-accent" onclick="window.keyboardShortcuts.hideHelp()">
              Zavřít (Esc)
            </button>
          </div>
        </div>
      </div>
    `;

    // Add modal to body
    document.body.insertAdjacentHTML('beforeend', modalHTML);

    // Close modal when clicking overlay
    const overlay = document.querySelector('.modal-overlay');
    if (overlay) {
      overlay.addEventListener('click', () => this.hideHelp());
    }
  }

  generateShortcutsTable() {
    let rows = '';
    for (const [key, shortcut] of Object.entries(this.shortcuts)) {
      // Skip hidden shortcuts
      if (shortcut.hidden) continue;

      const keyDisplay = key === '?' ? '?' : key.toUpperCase();
      rows += `
        <tr>
          <td><kbd class="keyboard-key">${keyDisplay}</kbd></td>
          <td>${shortcut.description}</td>
        </tr>
      `;
    }
    return rows;
  }

  announce(message) {
    // Create a live region for screen reader announcements
    let liveRegion = document.getElementById('sr-live-region');
    if (!liveRegion) {
      liveRegion = document.createElement('div');
      liveRegion.id = 'sr-live-region';
      liveRegion.setAttribute('role', 'status');
      liveRegion.setAttribute('aria-live', 'polite');
      liveRegion.setAttribute('aria-atomic', 'true');
      liveRegion.className = 'sr-only';
      document.body.appendChild(liveRegion);
    }

    liveRegion.textContent = message;

    // Clear after announcement
    setTimeout(() => {
      liveRegion.textContent = '';
    }, 1000);
  }
}

// Initialize keyboard shortcuts when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
  window.keyboardShortcuts = new KeyboardShortcuts();
});
