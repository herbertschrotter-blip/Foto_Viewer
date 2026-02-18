<#
.SYNOPSIS
Configuration Management für Foto_Viewer

.DESCRIPTION
Lädt und verwaltet Konfiguration aus config/settings.json.
Bietet typsicheren Zugriff auf Config-Werte mit Dot-Notation.

Funktionen:
- Read-FVConfig: Lädt settings.json und validiert Struktur
- Get-FVConfigValue: Holt einzelne Werte mit Dot-Notation (z.B. "Server.Port")
- Test-FVConfig: Validiert Config-Datei

.EXAMPLE
# Config laden
$config = Read-FVConfig
$config.Server.Port  # → 8787

.EXAMPLE
# Einzelnen Wert holen
$port = Get-FVConfigValue -Path "Server.Port"
Write-Host "Port: $port"  # → Port: 8787

.EXAMPLE
# Mit Default-Wert
$unknown = Get-FVConfigValue -Path "Unknown.Key" -Default 42
Write-Host $unknown  # → 42

.EXAMPLE
# Config validieren
if (Test-FVConfig) {
    Write-Host "Config ist gültig"
}

.NOTES
Autor: Herbert Schrotter
Version: 1.0.0
Erstellt: 2025-02-18
Projekt: Foto_Viewer

.LINK
https://github.com/herbertschrotter-blip/Foto_Viewer
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

function Get-ConfigPath {
    <#
    .SYNOPSIS
    Ermittelt Pfad zu settings.json
    
    .DESCRIPTION
    Berechnet den absoluten Pfad zur config/settings.json basierend
    auf dem Script-Verzeichnis. Wirft Exception wenn Datei nicht existiert.
    
    Pfad-Berechnung:
    $PSScriptRoot = .../03_Foto-Viewer/Lib/Core
    Split-Path -Parent (1x) = .../03_Foto-Viewer/Lib
    Split-Path -Parent (2x) = .../03_Foto-Viewer
    Join-Path config\settings.json = .../03_Foto-Viewer/config/settings.json
    
    .EXAMPLE
    $path = Get-ConfigPath
    
    .OUTPUTS
    String - Absoluter Pfad zu settings.json
    
    .NOTES
    Internal Helper - nicht für externen Aufruf gedacht
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $scriptRoot = $PSScriptRoot
        
        # Von Lib/Core/ zwei Ebenen hoch zu Projekt-Root
        # Lib/Core → Lib → 03_Foto-Viewer
        $libDir = Split-Path $scriptRoot -Parent      # Lib/Core → Lib
        $projectRoot = Split-Path $libDir -Parent      # Lib → 03_Foto-Viewer
        
        $configPath = Join-Path $projectRoot "config\settings.json"
        
        if (-not (Test-Path -LiteralPath $configPath)) {
            throw "Config-Datei nicht gefunden: $configPath"
        }
        
        Write-Verbose "Config-Pfad ermittelt: $configPath"
        return $configPath
        
    } catch {
        Write-Error "Fehler beim Ermitteln des Config-Pfads: $($_.Exception.Message)"
        throw
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Read-FVConfig {
    <#
    .SYNOPSIS
    Lädt Konfiguration aus settings.json
    
    .DESCRIPTION
    Lädt und parsed die config/settings.json Datei.
    Validiert erforderliche Sektionen und gibt PSCustomObject zurück.
    
    Erforderliche Sektionen:
    - Server
    - Thumbnails
    - Video
    - Logging
    - MediaExtensions
    
    .PARAMETER Path
    Optional: Pfad zu alternativer Config-Datei.
    Wenn nicht angegeben, wird config/settings.json verwendet.
    
    .EXAMPLE
    $config = Read-FVConfig
    Write-Host "Port: $($config.Server.Port)"
    
    .EXAMPLE
    $config = Read-FVConfig -Path "C:\custom\config.json"
    
    .EXAMPLE
    $config = Read-FVConfig -Verbose
    # Zeigt detaillierte Lade-Informationen
    
    .OUTPUTS
    PSCustomObject mit Config-Daten
    
    .NOTES
    Wirft Exception bei:
    - Datei nicht gefunden
    - Ungültiges JSON
    - Fehlende erforderliche Sektionen
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    
    try {
        # Config-Pfad ermitteln
        if (-not $Path) {
            $Path = Get-ConfigPath
        }
        
        Write-Verbose "Lade Config: $Path"
        
        # JSON laden und parsen
        $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $json | ConvertFrom-Json -ErrorAction Stop
        
        # Basis-Validierung: Erforderliche Sektionen prüfen
        $requiredSections = @('Server', 'Thumbnails', 'Video', 'Logging', 'MediaExtensions')
        
        foreach ($section in $requiredSections) {
            if (-not $config.PSObject.Properties[$section]) {
                throw "Fehlende Config-Sektion: $section"
            }
        }
        
        Write-Verbose "Config erfolgreich geladen und validiert"
        Write-Verbose "  Server.Port: $($config.Server.Port)"
        Write-Verbose "  Thumbnails.Size: $($config.Thumbnails.Size)"
        Write-Verbose "  Logging.Level: $($config.Logging.Level)"
        
        return $config
        
    } catch [System.IO.FileNotFoundException] {
        Write-Error "Config-Datei nicht gefunden: $Path"
        throw
    } catch [System.ArgumentException] {
        Write-Error "Ungültiges JSON in Config-Datei: $Path"
        throw
    } catch {
        Write-Error "Fehler beim Laden der Config: $($_.Exception.Message)"
        throw
    }
}

function Get-FVConfigValue {
    <#
    .SYNOPSIS
    Holt spezifischen Config-Wert mit Dot-Notation
    
    .DESCRIPTION
    Ermöglicht Zugriff auf verschachtelte Config-Werte mit Punkt-Notation.
    Beispiel: "Server.Port" → 8787
    
    Navigiert durch die Config-Hierarchie und gibt den Wert zurück.
    Optional kann ein Default-Wert angegeben werden.
    
    .PARAMETER Path
    Dot-Notation Pfad zum Wert (z.B. "Server.Port" oder "Thumbnails.Size")
    
    .PARAMETER Config
    Optional: Bereits geladenes Config-Objekt.
    Wenn nicht angegeben, wird Config neu geladen.
    Performance-Tipp: Config einmal laden und wiederverwenden.
    
    .PARAMETER Default
    Optional: Default-Wert wenn Pfad nicht existiert.
    Wenn nicht angegeben und Pfad nicht gefunden, wird Exception geworfen.
    
    .EXAMPLE
    $port = Get-FVConfigValue -Path "Server.Port"
    Write-Host "Port: $port"  # → Port: 8787
    
    .EXAMPLE
    # Config wiederverwenden (Performance)
    $config = Read-FVConfig
    $size = Get-FVConfigValue -Path "Thumbnails.Size" -Config $config
    $quality = Get-FVConfigValue -Path "Thumbnails.Quality" -Config $config
    
    .EXAMPLE
    # Mit Default-Wert
    $unknown = Get-FVConfigValue -Path "Unknown.Key" -Default 42
    Write-Host $unknown  # → 42 (kein Fehler!)
    
    .OUTPUTS
    Object - Typ abhängig vom Config-Wert (String, Int, Boolean, Array, etc.)
    
    .NOTES
    Wirft Exception wenn Pfad nicht existiert und kein Default angegeben wurde
    #>
    
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter()]
        [PSCustomObject]$Config,
        
        [Parameter()]
        [object]$Default
    )
    
    try {
        # Config laden wenn nicht übergeben
        if (-not $Config) {
            $Config = Read-FVConfig
        }
        
        Write-Verbose "Hole Config-Wert: $Path"
        
        # Pfad splitten (z.B. "Server.Port" → @("Server", "Port"))
        $parts = $Path -split '\.'
        $current = $Config
        
        # Navigation durch Objekt-Hierarchie
        foreach ($part in $parts) {
            if ($current.PSObject.Properties[$part]) {
                $current = $current.$part
                Write-Verbose "  → $part gefunden"
            } else {
                # Pfad nicht gefunden
                if ($PSBoundParameters.ContainsKey('Default')) {
                    Write-Verbose "  → $part nicht gefunden, verwende Default: $Default"
                    return $Default
                }
                throw "Config-Pfad nicht gefunden: $Path (fehlender Teil: $part)"
            }
        }
        
        Write-Verbose "Wert gefunden: $current"
        return $current
        
    } catch {
        Write-Error "Fehler beim Abrufen von Config-Wert '$Path': $($_.Exception.Message)"
        throw
    }
}

function Test-FVConfig {
    <#
    .SYNOPSIS
    Validiert Config-Datei
    
    .DESCRIPTION
    Prüft ob config/settings.json existiert, gültig ist
    und alle erforderlichen Sektionen enthält.
    
    Gibt $true zurück wenn Config valid, sonst $false.
    Schreibt keine Fehler, nur Verbose-Output.
    
    .EXAMPLE
    if (Test-FVConfig) {
        Write-Host "Config OK"
    } else {
        Write-Host "Config ungültig"
    }
    
    .EXAMPLE
    # Mit Verbose für Details
    Test-FVConfig -Verbose
    
    .OUTPUTS
    Boolean - $true wenn Config valid, sonst $false
    
    .NOTES
    Verwendet Read-FVConfig intern mit ErrorAction Stop
    #>
    
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $config = Read-FVConfig -ErrorAction Stop
        Write-Verbose "Config-Validierung erfolgreich"
        return $true
        
    } catch {
        Write-Verbose "Config-Validierung fehlgeschlagen: $($_.Exception.Message)"
        return $false
    }
}