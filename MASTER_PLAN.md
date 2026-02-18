# FOTO_VIEWER - NEUBAU MASTER PLAN

**Version:** 1.0  
**Erstellt:** 2025-02-18  
**Projekt:** Kompletter Neubau von PhotoFolder als Foto_Viewer

---

## ⚠️ HINWEIS

Dies ist eine **Kurzfassung** des Master Plans.  
Die vollständige Version mit allen Details findest du in der Claude-Konversation.

Dieser Plan dient als **Schnellreferenz** während der Entwicklung.

---

## 📋 ÄNDERUNGS-KATEGORIEN

### ✅ MUSS GEÄNDERT WERDEN (Blocker)
1. **Lib_PhotoGallery_UI.ps1** (1500 Zeilen HTML in Here-Strings)
2. **PhotoFolder-ReviewAndDelete.ps1** (1050 Zeilen Monolith)
3. **Lib_VideoThumbs.ps1** (komplex, fragiles Regex-Parsing)

### 🔨 SOLLTE GEÄNDERT WERDEN (Best Practices)
4. Kein Logging-System (nur Console)
5. Hardcoded Configuration
6. Keine Tests
7. State-Management (globale Variablen)

---

## 🏗️ NEUE ARCHITEKTUR

\\\
Foto_Viewer/
│
├── config/
│   └── settings.json
│
├── templates/
│   ├── index.html
│   ├── css/ (main.css, viewer.css, cards.css)
│   └── js/ (app.js, viewer.js, api.js, state.js)
│
├── Lib/
│   ├── Core/ (Config, Logging, State)
│   ├── HTTP/ (Server, Router, Request, Response)
│   ├── FileSystem/ (PathSecurity, Scanner, FileOps)
│   ├── Media/ (VideoMetadata, VideoConvert, Thumbnails, Streaming)
│   ├── UI/ (TemplateEngine, Components)
│   └── Utils/ (Dialogs, Archives)
│
├── API/
│   ├── API_Gallery.ps1
│   ├── API_Media.ps1
│   ├── API_Video.ps1
│   ├── API_FileOps.ps1
│   └── API_System.ps1
│
├── Tests/ (*.Tests.ps1)
├── Tools/ffmpeg/
├── Foto_Viewer.ps1 (Main Entry Point - KLEIN!)
└── start.bat
\\\

---

## 🔢 AUFBAU-REIHENFOLGE (15 SCHRITTE)

### **PHASE 1: FUNDAMENT (3-4h)**
- [x] **Schritt 1:** Projekt-Setup (30min) ✅
- [ ] **Schritt 2:** Core-Libs (1h) - Config, Logging, State
- [ ] **Schritt 3:** HTTP-Fundament (1.5h) - Server, Router, Request, Response

### **PHASE 2: FILESYSTEM & MEDIA (3-4h)**
- [ ] **Schritt 4:** FileSystem-Libs (1h) - PathSecurity, Scanner, FileOps
- [ ] **Schritt 5:** Video-Metadata NEU (1.5h) - FFprobe JSON statt Regex
- [ ] **Schritt 6:** Thumbnails & Conversion (1.5h)

### **PHASE 3: TEMPLATE-SYSTEM (2-3h)**
- [ ] **Schritt 7:** Template-Engine (1.5h)
- [ ] **Schritt 8:** Frontend (HTML/CSS/JS) (1.5h)

### **PHASE 4: API-ENDPOINTS (2-3h)**
- [ ] **Schritt 9:** Gallery-API (45min)
- [ ] **Schritt 10:** Media-API (1h)
- [ ] **Schritt 11:** Video-API (1h)
- [ ] **Schritt 12:** FileOps-API (45min)

### **PHASE 5: INTEGRATION & POLISH (2h)**
- [ ] **Schritt 13:** Main Entry Point (30min)
- [ ] **Schritt 14:** Testing (1h)
- [ ] **Schritt 15:** Dokumentation (30min)

**GESAMT:** 12-16 Stunden

---

## 🎯 PRINZIPIEN

1. **SCHRITTWEISE** - Kein Big-Bang, nach jedem Schritt lauffähig
2. **TESTBAR** - Von Anfang an, Pester-Tests
3. **MODULAR** - Klare Trennung, Single-Responsibility
4. **DOKUMENTIERT** - Standards einhalten, Comment-Based-Help
5. **LAUFFÄHIG** - Nach jedem Schritt funktioniert die App

---

## ✅ NACH JEDEM SCHRITT

1. **TESTEN** - Funktioniert der Schritt?
2. **COMMITTEN** - Hybrid-Format verwenden
3. **WARTEN** - User gibt OK
4. **NÄCHSTER SCHRITT** - Erst nach Bestätigung weiter!

---

## 🚀 WICHTIGE ENTSCHEIDUNGEN

1. **FFprobe statt Regex-Parsing**
   - JSON-Output ist zuverlässiger
   - fprobe -print_format json

2. **Template-System statt Here-Strings**
   - HTML/CSS/JS in separaten Dateien
   - Syntax-Highlighting in VSCode

3. **Router-Pattern statt Switch**
   - Register-FVRoute -Path -Method -Handler
   - Sauberere API-Organisation

4. **Structured Logging statt Console-only**
   - File + Console
   - Log-Levels, Rotation

5. **Config-File statt Hardcoded**
   - settings.json für alle Einstellungen
   - Leicht anpassbar ohne Code-Änderung

---

## 📊 MIGRATION-STRATEGIE

### **PORTIERT:**
- ✅ Lib_Dialogs.ps1 → Lib/Utils/
- ✅ Lib_ArchiveExtractor.ps1 → Lib/Utils/Lib_Archives.ps1
- ✅ Lib_FastScan.ps1 → Lib/FileSystem/Lib_Scanner.ps1
- ✅ Lib_FlattenAndMove.ps1 → Lib/FileSystem/Lib_FileOps.ps1

### **NEU GESCHRIEBEN:**
- 🔨 Lib_Http.ps1 → Lib/HTTP/* (4 Dateien)
- 🔨 Lib_FileSystem.ps1 → Lib/FileSystem/Lib_PathSecurity.ps1
- 🔨 Lib_VideoThumbs.ps1 → Lib/Media/* (4 Dateien, FFprobe JSON!)
- 🔨 Lib_PhotoGallery_UI.ps1 → templates/* + Lib/UI/*
- 🔨 PhotoFolder-ReviewAndDelete.ps1 → Foto_Viewer.ps1 + API/*

---

## 🎯 SUCCESS-KRITERIEN

### **FUNKTIONAL:**
- Alle Features aus PhotoFolder vorhanden
- Video-Conversion funktioniert
- Löschen/Verschieben/Flatten arbeitet
- UI responsiv und schnell

### **CODE-QUALITÄT:**
- Alle Libs < 500 Zeilen
- Main-Script < 100 Zeilen
- Pester-Tests grün
- Standards eingehalten

### **WARTBARKEIT:**
- HTML/CSS/JS in separaten Dateien
- Klare Modul-Struktur
- Dokumentation vorhanden

### **PERFORMANCE:**
- Parallel-Processing (PS7)
- Lazy Loading
- Cache-System
- HLS-Streaming

---

## 📝 NÄCHSTER SCHRITT

**→ SCHRITT 2: CORE-LIBS (1h)**

Erstellen:
1. Lib/Core/Lib_Config.ps1
   - Read-FVConfig
   - Get-FVConfigValue
   
2. Lib/Core/Lib_Logging.ps1
   - Write-FVLog (File + Console)
   - Log-Levels: Debug, Info, Warn, Error
   
3. Lib/Core/Lib_State.ps1
   - Initialize-FVState
   - Get-FVState
   - Set-FVState

**Test:** Config laden, Log schreiben, State setzen/abrufen

---

**Für vollständige Details siehe Claude-Konversation!**