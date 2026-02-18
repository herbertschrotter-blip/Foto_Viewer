# 🖼️ Foto_Viewer

**Professional Photo & Video Management with Web UI**

> Moderne PowerShell-basierte Web-App für lokales Photo/Video-Management mit Browser-Interface.

---

## ✨ Features

### 📁 **Media-Management**
- ✅ Rekursiver Scanner (18 Formate: JPG, PNG, WebP, MP4, AVI, MKV, etc.)
- ✅ Collapsible Folder Cards (10 Preview-Thumbnails pro Ordner)
- ✅ Lazy Loading (Medien on-demand)
- ✅ Archive-Extraktion (ZIP/7z automatisch vor Scan)
- ✅ Löschen (Papierkorb oder permanent)
- ✅ Verschieben (mit Dialog-Auswahl)
- ✅ Flatten & Move (verschachtelte Strukturen vereinfachen)

### 🎬 **Video-Features**
- ✅ Automatische Thumbnail-Generierung (FFmpeg)
- ✅ Parallel Processing (PowerShell 7: bis zu 8x schneller)
- ✅ Video-Metadaten (Codec, Format, Auflösung, Dauer, Kompatibilität)
- ✅ HLS-Streaming (HTTP Live Streaming mit 2s Chunks)
- ✅ Lazy Video-Conversion (DivX/XviD/WMV → H.264 on-demand)
- ✅ Range-Request-Support (Video-Spulen)
- ✅ VLC-Integration (Fallback für inkompatible Videos)

### 🌐 **Web-Interface**
- ✅ Lightbox Viewer (Vollbild-Overlay)
- ✅ Tastatur-Navigation (←/→/ESC)
- ✅ Maus-Navigation (Click left/right)
- ✅ Dateiname-Anzeige über Viewer
- ✅ Dunkles Theme (Grüne Akzente)
- ✅ Responsive Design

### 🔒 **Sicherheit & Performance**
- ✅ Path-Traversal-Schutz (keine ../ Attacken)
- ✅ Cache-System (schneller Re-Scan)
- ✅ Strukturiertes Logging (File + Console)
- ✅ Background-Jobs (nicht-blockierend)
- ✅ Template-System (HTML/CSS/JS getrennt)

---

## 🚀 Quick Start

### **Voraussetzungen**
- Windows 10/11
- PowerShell 5.1+ (empfohlen: PowerShell 7 für Parallel-Processing)
- FFmpeg (in \Tools/ffmpeg/\ ablegen)

### **Installation**

1. **FFmpeg herunterladen:**
   - Download: [https://www.gyan.dev/ffmpeg/builds/](https://www.gyan.dev/ffmpeg/builds/)
   - Extrahiere \fmpeg.exe\ und \fprobe.exe\ nach \Tools/ffmpeg/\

2. **Foto_Viewer starten:**
   \\\powershell
   .\Foto_Viewer.ps1
   \\\
   
   oder mit Parameter:
   \\\powershell
   .\Foto_Viewer.ps1 -RootPath "C:\Photos"
   \\\

3. **Browser öffnet automatisch:** \http://localhost:8787\

---

## ⚙️ Konfiguration

Bearbeite \config/settings.json\:

\\\json
{
  "Server": {
    "Port": 8787
  },
  "Thumbnails": {
    "Size": 140,
    "Quality": 5
  },
  "Video": {
    "ChunkDuration": 2,
    "ConversionPreset": "veryfast"
  }
}
\\\

---

## 📚 Architektur

\\\
Foto_Viewer/
├── config/              # Konfiguration
├── templates/           # HTML/CSS/JS (getrennt!)
├── Lib/                 # PowerShell-Bibliotheken
│   ├── Core/           # Config, Logging, State
│   ├── HTTP/           # Server, Router, Request/Response
│   ├── FileSystem/     # Path-Security, Scanner, FileOps
│   ├── Media/          # Video-Metadata, Conversion, Thumbnails
│   ├── UI/             # Template-Engine, Components
│   └── Utils/          # Dialogs, Archives
├── API/                 # API-Endpoints
├── Tests/               # Pester-Tests
└── Foto_Viewer.ps1     # Main Entry Point
\\\

**Unterschiede zu PhotoFolder:**
- ✅ Template-System (kein HTML in Here-Strings)
- ✅ FFprobe JSON (kein Regex-Parsing)
- ✅ Router-basierte API (statt Switch)
- ✅ Strukturiertes Logging
- ✅ Pester-Tests

---

## 🧪 Tests

\\\powershell
# Pester installieren
Install-Module -Name Pester -Force

# Tests ausführen
Invoke-Pester -Path Tests\
\\\

---

## 📖 API-Dokumentation

### **Gallery**
- \GET /\ - Main Page (HTML)
- \POST /api/scan\ - Re-Scan auslösen

### **Media**
- \GET /api/img?path=xxx\ - Image/Video ausliefern
- \GET /api/thumb?path=xxx\ - Video-Thumbnail

### **Video**
- \GET /api/video/metadata?path=xxx\ - Metadaten
- \POST /api/video/convert\ - HLS-Conversion starten
- \GET /api/video/hls?path=xxx\ - HLS-Playlist

### **FileOps**
- \POST /api/delete\ - Löschen (Papierkorb/Hard)
- \POST /api/move\ - Verschieben
- \POST /api/flatten\ - Flatten & Move

### **System**
- \POST /api/root/change\ - Root wechseln
- \POST /api/shutdown\ - Server beenden

---

## 📝 Changelog

Siehe [CHANGELOG.md](CHANGELOG.md)

---

## 🤝 Migration von PhotoFolder

Foto_Viewer ist der professionelle Nachfolger von PhotoFolder (aus 01_Scripte_Sammlung).

**Verbesserungen:**
- ✅ Bessere Code-Struktur (modular, testbar)
- ✅ Template-System (HTML/CSS/JS getrennt)
- ✅ Zuverlässigere Video-Metadaten (FFprobe JSON)
- ✅ Strukturiertes Logging
- ✅ Pester-Tests

**PhotoFolder bleibt funktionsfähig** (Wartungsmodus) in 01_Scripte_Sammlung.

---

## 📄 Lizenz

Dieses Projekt ist für den persönlichen Gebrauch.

---

## 👤 Autor

**Herbert Schrotter**  
GitHub: [@herbertschrotter-blip](https://github.com/herbertschrotter-blip)

---

## 🎯 Roadmap

- [x] Projekt-Setup
- [ ] Phase 1: Core-Libs (Config, Logging, HTTP)
- [ ] Phase 2: FileSystem & Media
- [ ] Phase 3: Template-System
- [ ] Phase 4: API-Endpoints
- [ ] Phase 5: Integration & Tests
- [ ] v1.0.0 Release

Siehe [MASTER_PLAN.md](MASTER_PLAN.md) für Details.