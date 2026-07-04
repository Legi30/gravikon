// Keyboard Shortcuts System
// Provides keyboard navigation (the shortcut list is documented on /o-aplikaci)

class KeyboardShortcuts {
  constructor() {
    this.shortcuts = {
      'd': { action: () => this.navigate('/dashboard'), description: 'Otevřít Přehled' },
      's': { action: () => this.navigate('/meetings'), description: 'Otevřít seznam Schůzek' },
      'g': { action: () => this.navigate('/galaxy'), description: 'Otevřít mapu Galaxie' },
      'n': { action: () => this.navigate('/meetings/new'), description: 'Nová schůzka' },
      'o': { action: () => this.navigate('/o-aplikaci'), description: 'O aplikaci' }
    };

    document.addEventListener('keydown', (e) => this.handleKeyPress(e));
  }

  handleKeyPress(event) {
    // Ignore if user is typing in an input field
    const activeElement = document.activeElement;
    const isInputField = activeElement.tagName === 'INPUT' ||
                        activeElement.tagName === 'TEXTAREA' ||
                        activeElement.tagName === 'SELECT' ||
                        activeElement.isContentEditable;

    if (isInputField) {
      return;
    }

    // Ignore key combinations (browser shortcuts like Ctrl+D must keep working)
    if (event.ctrlKey || event.metaKey || event.altKey) {
      return;
    }

    const shortcut = this.shortcuts[event.key];
    if (shortcut) {
      event.preventDefault();
      shortcut.action();
    }
  }

  navigate(url) {
    window.location.href = url;
  }
}

// Initialize keyboard shortcuts when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
  window.keyboardShortcuts = new KeyboardShortcuts();
  if (window.Logger) window.Logger.log('Keyboard shortcuts initialized.');
});
