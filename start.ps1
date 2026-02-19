<#
.SYNOPSIS
Foto_Viewer - Main Application

.DESCRIPTION
Startet den Foto_Viewer Web-Server mit Gallery-Funktionalität.

Features:
- Photo & Video Management
- Web-basierte Gallery-UI
- Thumbnail-Generierung
- Video-Streaming
- Multi-Frame Video-Previews

.PARAMETER Port
HTTP-Server Port (Default: 8888)

.PARAMETER RootPath
Pfad zum Medien-Ordner (Optional, Dialog wird angezeigt wenn nicht angegeben)

.PARAMETER LogLevel
Logging-Level: Debug, Info, Warn, Error (Default: Info)

.EXAMPLE
.\start.ps1

.EXAMPLE
.\start.ps1 -Port 8080 -RootPath "C:\Photos"

.EXAMPLE
.\start.ps1 -LogLevel Debug

.NOTES
Autor: Herbert Schrotter
Version: 1.8.0
Erstellt: 2025-02-18
Projekt: Foto_Viewer

Requirements:
- PowerShell 5.1+
- FFmpeg (für Videos)

.LINK
https://github.com/herbertschrotter-blip/Foto_Viewer
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1024, 65535)]
    [int]$Port = 8888,
    
    [Parameter()]
    [string]$RootPath,
    
    [Parameter()]
    [ValidateSet('Debug', 'Info', 'Warn', 'Error')]
    [string]$LogLevel = 'Info'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# BANNER
# ============================================================================

$banner = @"

  ███████╗ ██████╗ ████████╗ ██████╗     ██╗   ██╗██╗███████╗██╗    ██╗███████╗██████╗ 
  ██╔════╝██╔═══██╗╚══██╔══╝██╔═══██╗    ██║   ██║██║██╔════╝██║    ██║██╔════╝██╔══██╗
  █████╗  ██║   ██║   ██║   ██║   ██║    ██║   ██║██║█████╗  ██║ █╗ ██║█████╗  ██████╔╝
  ██╔══╝  ██║   ██║   ██║   ██║   ██║    ╚██╗ ██╔╝██║██╔══╝  ██║███╗██║██╔══╝  ██╔══██╗
  ██║     ╚██████╔╝   ██║   ╚██████╔╝     ╚████╔╝ ██║███████╗╚███╔███╔╝███████╗██║  ██║
  ╚═╝      ╚═════╝    ╚═╝    ╚═════╝       ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝
                                                                                          
  Professional Photo & Video Management with Web UI
  v1.8.0 | PowerShell Edition
  
"@

Write-Host $banner -ForegroundColor Cyan

# ============================================================================
# LOAD LIBRARIES
# ============================================================================

Write-Host "Lade Libraries..." -ForegroundColor Yellow

$libs = @(
    # Core
    "Lib\Core\Lib_Config.ps1",
    "Lib\Core\Lib_Logging.ps1",
    "Lib\Core\Lib_State.ps1",
    
    # HTTP
    "Lib\HTTP\Lib_HttpServer.ps1",
    "Lib\HTTP\Lib_Router.ps1",
    "Lib\HTTP\Lib_Request.ps1",
    "Lib\HTTP\Lib_Response.ps1",
    
    # FileSystem & Media
    "Lib\FileSystem\Lib_Scanner.ps1",
    "Lib\Media\Lib_VideoMetadata.ps1",
    "Lib\Media\Lib_Thumbnails.ps1",
    
    # UI & API
    "Lib\UI\Lib_TemplateEngine.ps1",
    "Lib\API\Lib_API_Gallery.ps1",
    "Lib\API\Lib_API_Assets.ps1",
    "Lib\API\Lib_API_Settings.ps1",
    "Lib\API\Lib_API_Folders.ps1"
)

$loadedCount = 0
foreach ($lib in $libs) {
    $libPath = Join-Path $PSScriptRoot $lib
    
    if (-not (Test-Path $libPath)) {
        Write-Host "  [FEHLER] FEHLT: $lib" -ForegroundColor Red
        exit 1
    }
    
    try {
        . $libPath
        $loadedCount++
    } catch {
        Write-Host "  [FEHLER] beim Laden: $lib" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  [OK] $loadedCount Libraries geladen" -ForegroundColor Green

# ============================================================================
# DEBUG: TEMPLATE-ENGINE CHECK
# ============================================================================

Write-Host ""
Write-Host "DEBUG: Template-Engine Check:" -ForegroundColor Magenta
if (Get-Command Resolve-FVTemplateConditionals -ErrorAction SilentlyContinue) {
    Write-Host "  [OK] Resolve-FVTemplateConditionals geladen" -ForegroundColor Green
} else {
    Write-Host "  [FEHLER] Resolve-FVTemplateConditionals FEHLT!" -ForegroundColor Red
    Write-Host "  Library wird neu geladen..." -ForegroundColor Yellow
    . (Join-Path $PSScriptRoot "Lib\UI\Lib_TemplateEngine.ps1")
}

if (Get-Command Resolve-FVTemplateLoops -ErrorAction SilentlyContinue) {
    Write-Host "  [OK] Resolve-FVTemplateLoops geladen" -ForegroundColor Green
} else {
    Write-Host "  [FEHLER] Resolve-FVTemplateLoops FEHLT!" -ForegroundColor Red
}

# Quick-Test
try {
    $testResult = Resolve-FVTemplateConditionals -Template "{{#if x}}Y{{/if}}" -Data @{x=$true}
    if ($testResult -eq "Y") {
        Write-Host "  [OK] Template-Engine funktioniert: Test erfolgreich" -ForegroundColor Green
    } else {
        Write-Host "  [WARNUNG] Template-Engine gibt falsches Ergebnis: '$testResult'" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [FEHLER] Template-Engine Test fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ============================================================================
# INITIALIZE
# ============================================================================

Write-Host "Initialisiere..." -ForegroundColor Yellow

# Logging
Initialize-FVLogging -Level $LogLevel

# State
Initialize-FVState

# Root-Path
if ($RootPath) {
    if (Test-Path -LiteralPath $RootPath) {
        Set-FVState -Key "RootPath" -Value $RootPath
        Write-Host "  [OK] Root-Path: $RootPath" -ForegroundColor Green
    } else {
        Write-Host "  [WARNUNG] Root-Path existiert nicht: $RootPath" -ForegroundColor Yellow
    }
} else {
    # ORDNER-DIALOG
    Write-Host "  Oeffne Ordner-Dialog..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.Windows.Forms
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Waehle Medien-Ordner (Fotos/Videos)"
    $folderBrowser.RootFolder = [System.Environment+SpecialFolder]::MyComputer
    
    $dialogResult = $folderBrowser.ShowDialog()
    
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $RootPath = $folderBrowser.SelectedPath
        Set-FVState -Key "RootPath" -Value $RootPath
        Write-Host "  [OK] Ordner gewaehlt: $RootPath" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Kein Ordner gewaehlt - Setup-Seite wird angezeigt" -ForegroundColor Yellow
    }
}

Write-Host ""

# ============================================================================
# REGISTER ROUTES
# ============================================================================

Write-Host "Registriere Routes..." -ForegroundColor Yellow

try {
    Register-FVGalleryRoutes
    Register-FVAssetRoutes
    Register-FVSettingsRoutes
    Register-FVFolderRoutes
    
    $routes = Get-FVRoutes
    Write-Host "  [OK] $($routes.Count) Routes registriert" -ForegroundColor Green
    
    if ($LogLevel -eq 'Debug') {
        Write-Host ""
        Write-Host "  DEBUG: Registrierte Routes:" -ForegroundColor Gray
        foreach ($route in $routes) {
            Write-Host "    - $($route.Method) $($route.Path)" -ForegroundColor Gray
        }
    }
    
} catch {
    Write-Host "  [FEHLER] beim Registrieren der Routes" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# START SERVER
# ============================================================================

Write-Host "Starte HTTP-Server..." -ForegroundColor Yellow

try {
    Start-FVHttpServer -Port $Port
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host " [OK] FOTO_VIEWER LAEUFT!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  URL: http://localhost:$Port" -ForegroundColor Cyan
    Write-Host "  Root-Path: $(if($RootPath){"$RootPath"}else{"Nicht gesetzt"})" -ForegroundColor Cyan
    Write-Host "  Log-Level: $LogLevel" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Druecke STRG+C zum Beenden..." -ForegroundColor Yellow
    Write-Host ""
    
    # Browser automatisch öffnen
    Write-Host "Oeffne Browser..." -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    Start-Process "http://localhost:$Port"
    
    # Keep alive
    while ($true) {
        Start-Sleep -Seconds 1
    }
    
} catch {
    Write-Host ""
    Write-Host "[FEHLER] beim Starten des Servers" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
    
} finally {
    Write-Host ""
    Write-Host "Stoppe Server..." -ForegroundColor Yellow
    Stop-FVHttpServer
    Write-Host "[OK] Server gestoppt" -ForegroundColor Green
}