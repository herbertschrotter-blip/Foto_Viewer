// Settings-Formular Handler
document.addEventListener('DOMContentLoaded', () => {
    const form = document.getElementById('settings-form');
    const browseBtn = document.getElementById('browse-btn');
    const resetBtn = document.getElementById('reset-btn');
    
    // Formular absenden
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        const formData = new FormData(form);
        const settings = {
            rootPath: formData.get('rootPath'),
            port: parseInt(formData.get('port')),
            thumbSize: parseInt(formData.get('thumbSize')),
            thumbQuality: parseInt(formData.get('thumbQuality')),
            videoFrames: parseInt(formData.get('videoFrames'))
        };
        
        try {
            const response = await fetch('/api/settings', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(settings)
            });
            
            if (response.ok) {
                const result = await response.json();
                alert('Einstellungen gespeichert!\n\n' + (result.needsRestart ? 'Server-Neustart erforderlich.' : 'Änderungen aktiv.'));
                if (!result.needsRestart) {
                    window.location.href = '/';
                }
            } else {
                alert('Fehler beim Speichern!');
            }
        } catch (error) {
            console.error('Fehler:', error);
            alert('Fehler beim Speichern der Einstellungen!');
        }
    });
    
    // Ordner durchsuchen (PowerShell-Dialog)
    browseBtn.addEventListener('click', async () => {
        try {
            const response = await fetch('/api/browse-folder');
            if (response.ok) {
                const result = await response.json();
                if (result.path) {
                    document.getElementById('rootPath').value = result.path;
                }
            }
        } catch (error) {
            alert('Ordner-Dialog konnte nicht geöffnet werden!\nBitte Pfad manuell eingeben.');
        }
    });
    
    // Zurücksetzen
    resetBtn.addEventListener('click', () => {
        if (confirm('Alle Einstellungen auf Standard zurücksetzen?')) {
            fetch('/api/settings/reset', { method: 'POST' })
                .then(response => {
                    if (response.ok) {
                        window.location.reload();
                    }
                });
        }
    });
});