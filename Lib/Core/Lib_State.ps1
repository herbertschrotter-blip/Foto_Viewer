<#
.SYNOPSIS
State Management für Foto_Viewer

.DESCRIPTION
Zentrales State-Management für Application-State.
Thread-Safe Hashtable für Laufzeit-Daten.

Funktionen:
- Initialize-FVState: Initialisiert State mit Default-Werten
- Get-FVState: Holt Wert aus State
- Set-FVState: Setzt Wert in State
- Clear-FVState: Löscht einzelnen State-Wert
- Reset-FVState: Setzt kompletten State zurück

State-Keys (Standard):
- ServerRunning: Boolean - Server läuft?
- RootPath: String - Aktueller Root-Pfad
- FolderCache: Array - Gescannte Ordner
- VideoMetadataCache: Hashtable - Video-Metadaten Cache
- LastScanTime: DateTime - Letzter Scan-Zeitpunkt

.EXAMPLE
# State initialisieren
Initialize-FVState

# Wert setzen
Set-FVState -Key "RootPath" -Value "C:\Photos"

# Wert abrufen
$root = Get-FVState -Key "RootPath"
Write-Host "Root: $root"  # → Root: C:\Photos

.EXAMPLE
# Mit Default-Wert
$unknown = Get-FVState -Key "Unknown" -Default "DefaultValue"
Write-Host $unknown  # → DefaultValue

.EXAMPLE
# State zurücksetzen
Reset-FVState
Initialize-FVState

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

# ============================================================================
# MODULE-LEVEL STATE
# ============================================================================

$script:FVState = $null
$script:FVStateLock = [System.Object]::new()

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Initialize-FVState {
    <#
    .SYNOPSIS
    Initialisiert Application-State
    
    .DESCRIPTION
    Erstellt neuen synchronized State und setzt Default-Werte.
    Muss einmal beim App-Start aufgerufen werden.
    
    Thread-Safe: Verwendet synchronized Hashtable für Multi-Threading-Szenarien.
    
    Standard-Keys:
    - ServerRunning: $false
    - RootPath: $null
    - FolderCache: $null
    - VideoMetadataCache: @{}
    - LastScanTime: $null
    
    .PARAMETER Reset
    Wenn $true, wird existierender State zurückgesetzt.
    Sonst wird nur initialisiert wenn noch kein State existiert.
    
    .EXAMPLE
    Initialize-FVState
    
    .EXAMPLE
    # State zurücksetzen
    Initialize-FVState -Reset
    
    .EXAMPLE
    Initialize-FVState -Verbose
    # Zeigt detaillierte Initialisierungs-Info
    
    .NOTES
    Sollte nur einmal beim App-Start aufgerufen werden.
    Bei Reset gehen alle Laufzeit-Daten verloren!
    #>
    
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Reset
    )
    
    try {
        [System.Threading.Monitor]::Enter($script:FVStateLock)
        
        if ($Reset -or $null -eq $script:FVState) {
            
            # Synchronized Hashtable erstellen (Thread-Safe)
            $script:FVState = [hashtable]::Synchronized(@{
                ServerRunning = $false
                RootPath = $null
                FolderCache = $null
                VideoMetadataCache = @{}
                LastScanTime = $null
            })
            
            Write-Verbose "State initialisiert"
            Write-Verbose "  Keys: $($script:FVState.Keys -join ', ')"
            
        } else {
            Write-Verbose "State bereits initialisiert (verwende -Reset zum Zurücksetzen)"
        }
        
    } catch {
        Write-Error "Fehler beim Initialisieren des States: $($_.Exception.Message)"
        throw
    } finally {
        [System.Threading.Monitor]::Exit($script:FVStateLock)
    }
}

function Get-FVState {
    <#
    .SYNOPSIS
    Holt Wert aus Application-State
    
    .DESCRIPTION
    Thread-Safe Zugriff auf State-Werte.
    
    Wenn Key nicht existiert:
    - Mit -Default Parameter: Gibt Default zurück
    - Ohne -Default Parameter: Wirft Exception
    
    .PARAMETER Key
    State-Key (z.B. "RootPath", "ServerRunning")
    
    .PARAMETER Default
    Optional: Default-Wert wenn Key nicht existiert.
    Wenn angegeben, wird keine Exception geworfen.
    
    .EXAMPLE
    $rootPath = Get-FVState -Key "RootPath"
    Write-Host "Root: $rootPath"
    
    .EXAMPLE
    # Mit Default-Wert
    $unknown = Get-FVState -Key "Unknown" -Default "DefaultValue"
    Write-Host $unknown  # → DefaultValue (kein Fehler!)
    
    .EXAMPLE
    # Prüfen ob Server läuft
    $running = Get-FVState -Key "ServerRunning"
    if ($running) {
        Write-Host "Server läuft"
    }
    
    .OUTPUTS
    Object - Typ abhängig vom State-Wert
    
    .NOTES
    Wirft Exception wenn:
    - State nicht initialisiert (Initialize-FVState fehlt)
    - Key nicht existiert UND kein Default angegeben
    #>
    
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,
        
        [Parameter()]
        [object]$Default
    )
    
    try {
        [System.Threading.Monitor]::Enter($script:FVStateLock)
        
        # State-Check
        if ($null -eq $script:FVState) {
            throw "State nicht initialisiert. Rufe Initialize-FVState auf."
        }
        
        # Key existiert?
        if ($script:FVState.ContainsKey($Key)) {
            $value = $script:FVState[$Key]
            Write-Verbose "State-Wert abgerufen: $Key = $value"
            return $value
        }
        
        # Key nicht gefunden
        if ($PSBoundParameters.ContainsKey('Default')) {
            Write-Verbose "State-Key nicht gefunden: $Key (verwende Default: $Default)"
            return $Default
        }
        
        throw "State-Key nicht gefunden: $Key"
        
    } catch {
        Write-Error "Fehler beim Abrufen von State-Wert '$Key': $($_.Exception.Message)"
        throw
    } finally {
        [System.Threading.Monitor]::Exit($script:FVStateLock)
    }
}

function Set-FVState {
    <#
    .SYNOPSIS
    Setzt Wert in Application-State
    
    .DESCRIPTION
    Thread-Safe Setzen von State-Werten.
    
    Wenn Key nicht existiert, wird er automatisch angelegt.
    Wenn Key existiert, wird Wert überschrieben.
    
    .PARAMETER Key
    State-Key (z.B. "RootPath", "ServerRunning")
    
    .PARAMETER Value
    Wert zum Setzen (beliebiger Typ)
    
    .EXAMPLE
    Set-FVState -Key "RootPath" -Value "C:\Photos"
    
    .EXAMPLE
    Set-FVState -Key "ServerRunning" -Value $true
    
    .EXAMPLE
    # Komplexe Objekte
    $cache = @{
        "video1.mp4" = @{ Codec = "h264"; Duration = 120 }
        "video2.avi" = @{ Codec = "xvid"; Duration = 90 }
    }
    Set-FVState -Key "VideoMetadataCache" -Value $cache
    
    .EXAMPLE
    Set-FVState -Key "LastScanTime" -Value (Get-Date) -Verbose
    
    .NOTES
    Wirft Exception wenn State nicht initialisiert
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,
        
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value
    )
    
    try {
        [System.Threading.Monitor]::Enter($script:FVStateLock)
        
        # State-Check
        if ($null -eq $script:FVState) {
            throw "State nicht initialisiert. Rufe Initialize-FVState auf."
        }
        
        # Wert setzen
        $script:FVState[$Key] = $Value
        Write-Verbose "State-Wert gesetzt: $Key = $Value"
        
    } catch {
        Write-Error "Fehler beim Setzen von State-Wert '$Key': $($_.Exception.Message)"
        throw
    } finally {
        [System.Threading.Monitor]::Exit($script:FVStateLock)
    }
}

function Clear-FVState {
    <#
    .SYNOPSIS
    Löscht einzelnen State-Wert
    
    .DESCRIPTION
    Entfernt einen Key komplett aus dem State.
    
    Wenn Key nicht existiert, passiert nichts (kein Fehler).
    
    .PARAMETER Key
    State-Key zum Löschen
    
    .EXAMPLE
    Clear-FVState -Key "FolderCache"
    
    .EXAMPLE
    Clear-FVState -Key "VideoMetadataCache" -Verbose
    
    .NOTES
    Wirft Exception wenn State nicht initialisiert
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )
    
    try {
        [System.Threading.Monitor]::Enter($script:FVStateLock)
        
        # State-Check
        if ($null -eq $script:FVState) {
            throw "State nicht initialisiert. Rufe Initialize-FVState auf."
        }
        
        # Key löschen
        if ($script:FVState.ContainsKey($Key)) {
            $script:FVState.Remove($Key)
            Write-Verbose "State-Key gelöscht: $Key"
        } else {
            Write-Verbose "State-Key existiert nicht: $Key (nichts zu löschen)"
        }
        
    } catch {
        Write-Error "Fehler beim Löschen von State-Key '$Key': $($_.Exception.Message)"
        throw
    } finally {
        [System.Threading.Monitor]::Exit($script:FVStateLock)
    }
}

function Reset-FVState {
    <#
    .SYNOPSIS
    Setzt kompletten State zurück
    
    .DESCRIPTION
    Löscht alle State-Werte und setzt auf $null.
    
    WARNUNG: Alle Laufzeit-Daten gehen verloren!
    Nach Reset muss Initialize-FVState erneut aufgerufen werden.
    
    .EXAMPLE
    Reset-FVState
    Initialize-FVState
    
    .EXAMPLE
    # Mit Bestätigung
    if (Read-Host "State zurücksetzen? (y/n)" -eq "y") {
        Reset-FVState
        Initialize-FVState
    }
    
    .NOTES
    Sollte nur verwendet werden wenn wirklich nötig (z.B. bei Tests)
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        [System.Threading.Monitor]::Enter($script:FVStateLock)
        
        $script:FVState = $null
        Write-Verbose "State zurückgesetzt"
        
    } catch {
        Write-Error "Fehler beim Zurücksetzen des States: $($_.Exception.Message)"
        throw
    } finally {
        [System.Threading.Monitor]::Exit($script:FVStateLock)
    }
}

function Get-FVStateKeys {
    <#
    .SYNOPSIS
    Listet alle State-Keys auf
    
    .DESCRIPTION
    Gibt Array aller vorhandenen State-Keys zurück.
    Nützlich für Debugging.
    
    .EXAMPLE
    $keys = Get-FVStateKeys
    Write-Host "State-Keys: $($keys -join ', ')"
    
    .EXAMPLE
    Get-FVStateKeys | ForEach-Object {
        $value = Get-FVState -Key $_
        Write-Host "$_ = $value"
    }
    
    .OUTPUTS
    String[] - Array von State-Keys
    
    .NOTES
    Wirft Exception wenn State nicht initialisiert
    #>
    
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    
    try {
        [System.Threading.Monitor]::Enter($script:FVStateLock)
        
        # State-Check
        if ($null -eq $script:FVState) {
            throw "State nicht initialisiert. Rufe Initialize-FVState auf."
        }
        
        $keys = @($script:FVState.Keys)
        Write-Verbose "State-Keys: $($keys -join ', ')"
        
        return $keys
        
    } catch {
        Write-Error "Fehler beim Abrufen der State-Keys: $($_.Exception.Message)"
        throw
    } finally {
        [System.Threading.Monitor]::Exit($script:FVStateLock)
    }
}