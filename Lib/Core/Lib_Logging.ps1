<#
.SYNOPSIS
Structured Logging für Foto_Viewer

.DESCRIPTION
Bietet strukturiertes Logging mit:
- Multiple Log-Levels (Debug, Info, Warn, Error)
- File + Console Output
- Automatische Rotation (max 10MB, 5 Dateien)
- Farbcodierung in Console
- Thread-Safe

Funktionen:
- Initialize-FVLogging: Konfiguriert Logging-System
- Write-FVLog: Schreibt Log-Nachricht in Datei und Console

.EXAMPLE
# Logging initialisieren
Initialize-FVLogging -Level Info

# Log-Nachricht schreiben
Write-FVLog -Level Info -Message "Server gestartet auf Port 8787"

.EXAMPLE
# Mit Debug-Level
Initialize-FVLogging -Level Debug -MaxFileSizeMB 20
Write-FVLog -Level Debug -Message "Detaillierte Debug-Info"

.EXAMPLE
# Mit Exception
try {
    # Riskante Operation
} catch {
    Write-FVLog -Level Error -Message "Operation fehlgeschlagen" -Exception $_
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
# MODULE-LEVEL VARIABLES
# ============================================================================

$script:FVLogConfig = @{
    LogDirectory = "logs"
    MaxFileSizeMB = 10
    MaxFiles = 5
    Level = "Info"  # Debug, Info, Warn, Error
}

$script:FVLogLevels = @{
    Debug = 0
    Info = 1
    Warn = 2
    Error = 3
}

$script:FVLogColors = @{
    Debug = "DarkGray"
    Info = "White"
    Warn = "Yellow"
    Error = "Red"
}

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

function Get-LogFilePath {
    <#
    .SYNOPSIS
    Ermittelt aktuellen Log-Datei-Pfad
    
    .DESCRIPTION
    Berechnet Pfad zur aktuellen Log-Datei basierend auf Datum.
    Erstellt Log-Verzeichnis falls nicht vorhanden.
    
    Format: foto-viewer_YYYY-MM-DD.log
    
    .EXAMPLE
    $path = Get-LogFilePath
    # → D:\...\03_Foto-Viewer\logs\foto-viewer_2025-02-18.log
    
    .OUTPUTS
    String - Absoluter Pfad zur Log-Datei
    
    .NOTES
    Internal Helper - nicht für externen Aufruf gedacht
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $scriptRoot = $PSScriptRoot
        $libDir = Split-Path $scriptRoot -Parent
        $projectRoot = Split-Path $libDir -Parent
        $logDir = Join-Path $projectRoot $script:FVLogConfig.LogDirectory
        
        # Log-Verzeichnis erstellen falls nicht vorhanden
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Log-Verzeichnis erstellt: $logDir"
        }
        
        $date = Get-Date -Format "yyyy-MM-dd"
        $logFileName = "foto-viewer_$date.log"
        
        return Join-Path $logDir $logFileName
        
    } catch {
        Write-Error "Fehler beim Ermitteln des Log-Pfads: $($_.Exception.Message)"
        throw
    }
}

function Test-LogRotation {
    <#
    .SYNOPSIS
    Prüft ob Log-Rotation nötig
    
    .DESCRIPTION
    Prüft aktuelle Log-Datei-Größe.
    Bei Überschreitung von MaxFileSizeMB wird Rotation durchgeführt:
    - Alte Logs werden umbenannt mit Timestamp
    - Logs über MaxFiles werden gelöscht
    
    .PARAMETER LogPath
    Pfad zur aktuellen Log-Datei
    
    .EXAMPLE
    Test-LogRotation -LogPath "C:\logs\app.log"
    
    .NOTES
    Internal Helper - nicht für externen Aufruf gedacht
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )
    
    try {
        if (-not (Test-Path -LiteralPath $LogPath)) {
            return  # Datei existiert noch nicht
        }
        
        $fileInfo = Get-Item -LiteralPath $LogPath -ErrorAction Stop
        $sizeMB = $fileInfo.Length / 1MB
        
        if ($sizeMB -gt $script:FVLogConfig.MaxFileSizeMB) {
            Write-Verbose "Log-Rotation erforderlich ($sizeMB MB > $($script:FVLogConfig.MaxFileSizeMB) MB)"
            
            $dir = Split-Path -Parent $LogPath
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
            $extension = [System.IO.Path]::GetExtension($LogPath)
            
            # Alte Logs löschen (MaxFiles erreicht)
            $existingLogs = Get-ChildItem -LiteralPath $dir -Filter "${baseName}*${extension}" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending
            
            if ($existingLogs.Count -ge $script:FVLogConfig.MaxFiles) {
                $toDelete = $existingLogs | Select-Object -Skip ($script:FVLogConfig.MaxFiles - 1)
                foreach ($log in $toDelete) {
                    Remove-Item -LiteralPath $log.FullName -Force -ErrorAction SilentlyContinue
                    Write-Verbose "Altes Log gelöscht: $($log.Name)"
                }
            }
            
            # Aktuelles Log umbenennen
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $newName = "${baseName}_${timestamp}${extension}"
            $newPath = Join-Path $dir $newName
            
            Move-Item -LiteralPath $LogPath -Destination $newPath -Force -ErrorAction Stop
            Write-Verbose "Log rotiert: $newName"
        }
        
    } catch {
        Write-Verbose "Fehler bei Log-Rotation: $($_.Exception.Message)"
        # Rotation-Fehler nicht fatal - weiter loggen
    }
}

function Get-LogLevelValue {
    <#
    .SYNOPSIS
    Konvertiert Log-Level String zu numerischem Wert
    
    .DESCRIPTION
    Mapping:
    - Debug = 0
    - Info = 1
    - Warn = 2
    - Error = 3
    
    .PARAMETER Level
    Log-Level als String
    
    .EXAMPLE
    $value = Get-LogLevelValue -Level "Info"
    # → 1
    
    .OUTPUTS
    Int32 - Numerischer Level-Wert
    
    .NOTES
    Internal Helper - nicht für externen Aufruf gedacht
    #>
    
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Level
    )
    
    if ($script:FVLogLevels.ContainsKey($Level)) {
        return $script:FVLogLevels[$Level]
    }
    
    # Fallback auf Info
    return $script:FVLogLevels['Info']
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Initialize-FVLogging {
    <#
    .SYNOPSIS
    Initialisiert Logging-System
    
    .DESCRIPTION
    Konfiguriert Logging mit Settings aus Config oder Parametern.
    Muss einmal beim App-Start aufgerufen werden.
    
    Wenn Parameter nicht angegeben, werden Defaults verwendet.
    
    .PARAMETER LogDirectory
    Verzeichnis für Log-Dateien (Default: logs)
    Relativ zu Projekt-Root
    
    .PARAMETER MaxFileSizeMB
    Maximale Größe pro Log-Datei in MB (Default: 10)
    Bei Überschreitung wird rotiert
    
    .PARAMETER MaxFiles
    Maximale Anzahl rotierter Log-Dateien (Default: 5)
    Älteste werden automatisch gelöscht
    
    .PARAMETER Level
    Minimum Log-Level: Debug, Info, Warn, Error (Default: Info)
    Nachrichten unter diesem Level werden nicht geloggt
    
    .EXAMPLE
    Initialize-FVLogging
    
    .EXAMPLE
    Initialize-FVLogging -Level Debug -MaxFileSizeMB 20
    
    .EXAMPLE
    # Mit Config
    $config = Read-FVConfig
    Initialize-FVLogging -Level $config.Logging.Level -MaxFileSizeMB $config.Logging.MaxFileSizeMB
    
    .NOTES
    Sollte nur einmal beim App-Start aufgerufen werden
    #>
    
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory = "logs",
        
        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$MaxFileSizeMB = 10,
        
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxFiles = 5,
        
        [Parameter()]
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')]
        [string]$Level = 'Info'
    )
    
    try {
        $script:FVLogConfig.LogDirectory = $LogDirectory
        $script:FVLogConfig.MaxFileSizeMB = $MaxFileSizeMB
        $script:FVLogConfig.MaxFiles = $MaxFiles
        $script:FVLogConfig.Level = $Level
        
        Write-Verbose "Logging initialisiert:"
        Write-Verbose "  Level: $Level"
        Write-Verbose "  Directory: $LogDirectory"
        Write-Verbose "  MaxFileSizeMB: $MaxFileSizeMB"
        Write-Verbose "  MaxFiles: $MaxFiles"
        
    } catch {
        Write-Error "Fehler beim Initialisieren des Loggings: $($_.Exception.Message)"
        throw
    }
}

function Write-FVLog {
    <#
    .SYNOPSIS
    Schreibt Log-Nachricht
    
    .DESCRIPTION
    Schreibt formatierte Log-Nachricht in Datei und Console.
    Berücksichtigt konfiguriertes Log-Level.
    
    Format: [YYYY-MM-DD HH:mm:ss] [LEVEL] Message
    
    Console-Ausgabe mit Farben:
    - Debug: DarkGray
    - Info: White
    - Warn: Yellow
    - Error: Red
    
    .PARAMETER Level
    Log-Level: Debug, Info, Warn, Error
    
    .PARAMETER Message
    Log-Nachricht (wird automatisch formatiert)
    
    .PARAMETER Exception
    Optional: Exception-Objekt für detailliertes Error-Logging
    Fügt Exception-Message und StackTrace hinzu
    
    .EXAMPLE
    Write-FVLog -Level Info -Message "Server gestartet auf Port 8787"
    
    .EXAMPLE
    Write-FVLog -Level Warn -Message "Config-Wert fehlt, verwende Default"
    
    .EXAMPLE
    try {
        Get-Item "C:\nonexistent.txt" -ErrorAction Stop
    } catch {
        Write-FVLog -Level Error -Message "Datei nicht gefunden" -Exception $_
    }
    
    .EXAMPLE
    Write-FVLog -Level Debug -Message "Detaillierte Debug-Info"
    # Wird nur geloggt wenn Level = Debug konfiguriert
    
    .NOTES
    Nachrichten unter dem konfigurierten Level werden ignoriert.
    Bei Logging-Fehlern wird trotzdem in Console geschrieben (Fallback).
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter()]
        [System.Management.Automation.ErrorRecord]$Exception
    )
    
    try {
        # Level-Check: Nachricht unter konfiguriertem Level → skip
        $currentLevelValue = Get-LogLevelValue -Level $script:FVLogConfig.Level
        $messageLevelValue = Get-LogLevelValue -Level $Level
        
        if ($messageLevelValue -lt $currentLevelValue) {
            return
        }
        
        # Timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Log-Eintrag formatieren
        $logEntry = "[$timestamp] [$Level] $Message"
        
        # Exception-Details anhängen
        if ($Exception) {
            $logEntry += "`n  Exception: $($Exception.Exception.Message)"
            if ($Exception.ScriptStackTrace) {
                $logEntry += "`n  StackTrace: $($Exception.ScriptStackTrace)"
            }
        }
        
        # File-Logging
        try {
            $logPath = Get-LogFilePath
            Test-LogRotation -LogPath $logPath
            Add-Content -LiteralPath $logPath -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        } catch {
            # File-Logging fehlgeschlagen → nur Console
            Write-Verbose "File-Logging fehlgeschlagen: $($_.Exception.Message)"
        }
        
        # Console-Logging (farbig)
        $color = $script:FVLogColors[$Level]
        Write-Host $logEntry -ForegroundColor $color
        
    } catch {
        # Fallback bei Logging-Fehler: Nur Console ohne Farbe
        Write-Warning "Logging-Fehler: $($_.Exception.Message)"
        Write-Host "[$Level] $Message" -ForegroundColor Red
    }
}