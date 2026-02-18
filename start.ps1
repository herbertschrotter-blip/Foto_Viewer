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
HTTP-Server Port (Default: 8787)

.PARAMETER RootPath
Pfad zum Medien-Ordner (Optional, kann später gesetzt werden)

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
Version: 1.5.0
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
    [int]$Port = 8787,
    
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
  v1.5.0 | PowerShell Edition
  
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
    "Lib\API\Lib_API_Assets.ps1"
)

$loadedCount = 0
foreach ($lib in $libs) {
    $libPath = Join-Path $PSScriptRoot $lib
    
    if (-not (Test-Path $libPath)) {
        Write-Host "  ✗ FEHLT: $lib" -ForegroundColor Red
        exit 1
    }
    
    try {
        . $libPath
        $loadedCount++
    } catch {
        Write-Host "  ✗ FEHLER beim Laden: $lib" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  ✓ $loadedCount Libraries geladen" -ForegroundColor Green
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
        Write-Host "  ✓ Root-Path: $RootPath" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Root-Path existiert nicht: $RootPath" -ForegroundColor Yellow
        Write-Host "    Bitte später setzen mit: Set-FVState -Key 'RootPath' -Value 'C:\Dein\Pfad'" -ForegroundColor Cyan
    }
} else {
    Write-Host "  ℹ️  Root-Path nicht gesetzt (später konfigurierbar)" -ForegroundColor Cyan
}

Write-Host ""

# ============================================================================
# REGISTER ROUTES
# ============================================================================

Write-Host "Registriere Routes..." -ForegroundColor Yellow

try {
    Register-FVGalleryRoutes
    Register-FVAssetRoutes
    
    $routes = Get-FVRoutes
    Write-Host "  ✓ $($routes.Count) Routes registriert" -ForegroundColor Green
    
    # DEBUG: Routes auflisten
    Write-Host "`n  DEBUG: Registrierte Routes:" -ForegroundColor Yellow
    foreach ($route in $routes) {
        Write-Host "    - $($route.Method) $($route.Path)" -ForegroundColor Cyan
    }
    Write-Host ""
    
} catch {
    Write-Host "  ✗ Fehler beim Registrieren der Routes" -ForegroundColor Red
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
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host " ✅ FOTO_VIEWER LÄUFT!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  🌐 URL: http://localhost:$Port" -ForegroundColor Cyan
    Write-Host "  📁 Root-Path: $(if($RootPath){"$RootPath"}else{"Nicht gesetzt"})" -ForegroundColor Cyan
    Write-Host "  📊 Log-Level: $LogLevel" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Drücke STRG+C zum Beenden..." -ForegroundColor Yellow
    Write-Host ""
    
    # Browser automatisch öffnen
    Write-Host "Öffne Browser..." -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    Start-Process "http://localhost:$Port"
    
    # Keep alive
    while ($true) {
        Start-Sleep -Seconds 1
    }
    
} catch {
    Write-Host "  ✗ Fehler beim Starten des Servers" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
    exit 1
    
} finally {
    Write-Host ""
    Write-Host "Stoppe Server..." -ForegroundColor Yellow
    Stop-FVHttpServer
    Write-Host "  ✓ Server gestoppt" -ForegroundColor Green
}