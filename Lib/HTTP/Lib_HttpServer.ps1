<#
.SYNOPSIS
HTTP-Server Management für Foto_Viewer

.DESCRIPTION
Verwaltet den HttpListener für den Web-Server.
Vereinfacht Start/Stop und Request-Handling.

Funktionen:
- Start-FVHttpServer: Startet HttpListener auf angegebenem Port
- Stop-FVHttpServer: Stoppt Server sauber
- Get-FVHttpServerStatus: Gibt aktuellen Server-Status zurück

Der Server läuft in einer Endlos-Schleife und wartet auf Requests.
Requests werden an den Router weitergeleitet (siehe Lib_Router.ps1).

.EXAMPLE
# Server starten
Start-FVHttpServer -Port 8787

# Server läuft jetzt und bedient Requests
# Beenden mit Ctrl+C oder Stop-FVHttpServer

.EXAMPLE
# Mit Callback-Funktion
Start-FVHttpServer -Port 8787 -RequestHandler {
    param($Context)
    # Custom Request-Handling
}

.NOTES
Autor: Herbert Schrotter
Version: 1.0.0
Erstellt: 2025-02-18
Projekt: Foto_Viewer

Benötigt:
- .NET HttpListener (in PowerShell enthalten)
- Admin-Rechte NICHT erforderlich für localhost

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

$script:FVHttpListener = $null
$script:FVHttpRunning = $false

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Start-FVHttpServer {
    <#
    .SYNOPSIS
    Startet HTTP-Server
    
    .DESCRIPTION
    Startet HttpListener auf angegebenem Port.
    Server läuft in Endlos-Schleife bis Stop-FVHttpServer aufgerufen wird
    oder ServerRunning-State auf $false gesetzt wird.
    
    Präfixe werden automatisch hinzugefügt:
    - http://localhost:{Port}/
    - http://127.0.0.1:{Port}/
    
    .PARAMETER Port
    Port auf dem Server lauschen soll (Default: 8787)
    
    .PARAMETER RequestHandler
    Optional: ScriptBlock der für jeden Request aufgerufen wird.
    Bekommt HttpListenerContext als Parameter.
    
    Wenn nicht angegeben, wird Router verwendet (Invoke-FVRoute).
    
    .EXAMPLE
    Start-FVHttpServer -Port 8787
    
    .EXAMPLE
    # Mit Custom-Handler
    Start-FVHttpServer -Port 8787 -RequestHandler {
        param($Context)
        $response = $Context.Response
        $html = "<h1>Hello World</h1>"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
    
    .EXAMPLE
    # Mit Verbose-Output
    Start-FVHttpServer -Port 8787 -Verbose
    
    .NOTES
    Blockiert bis Server gestoppt wird (Endlos-Schleife).
    Für Produktion: In separatem Runspace/Job ausführen.
    
    Benötigt KEINE Admin-Rechte für localhost/127.0.0.1.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 8787,
        
        [Parameter()]
        [scriptblock]$RequestHandler
    )
    
    try {
        # Prüfen ob bereits läuft
        if ($script:FVHttpRunning) {
            Write-Warning "Server läuft bereits"
            return
        }
        
        Write-Verbose "Initialisiere HttpListener..."
        
        # HttpListener erstellen
        $script:FVHttpListener = [System.Net.HttpListener]::new()
        
        # Präfixe hinzufügen
        $prefixes = @(
            "http://localhost:$Port/",
            "http://127.0.0.1:$Port/"
        )
        
        foreach ($prefix in $prefixes) {
            $script:FVHttpListener.Prefixes.Add($prefix)
            Write-Verbose "Präfix hinzugefügt: $prefix"
        }
        
        # Server starten
        $script:FVHttpListener.Start()
        $script:FVHttpRunning = $true
        
        Write-FVLog -Level Info -Message "HTTP-Server gestartet auf Port $Port"
        Write-Host ""
        Write-Host "══════════════════════════════════════════" -ForegroundColor Green
        Write-Host " ✅ SERVER LÄUFT" -ForegroundColor Green
        Write-Host "══════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        Write-Host "  URL: http://localhost:$Port" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Drücke Ctrl+C zum Beenden" -ForegroundColor Yellow
        Write-Host ""
        
        # State setzen (falls State-Lib verfügbar)
        try {
            Set-FVState -Key "ServerRunning" -Value $true -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "State-Lib nicht verfügbar (OK)"
        }
        
        # Request-Loop
        while ($script:FVHttpRunning) {
            try {
                # Auf Request warten (mit Timeout für sauberes Shutdown)
                $contextTask = $script:FVHttpListener.GetContextAsync()
                
                # Warte mit Timeout (ermöglicht Check von ServerRunning-State)
                $timeout = [System.TimeSpan]::FromSeconds(1)
                $completed = $contextTask.Wait($timeout)
                
                if (-not $completed) {
                    # Timeout → Check ServerRunning-State
                    try {
                        $stateRunning = Get-FVState -Key "ServerRunning" -Default $true -ErrorAction SilentlyContinue
                        if (-not $stateRunning) {
                            Write-Verbose "ServerRunning-State = false, beende Loop"
                            break
                        }
                    } catch {
                        # State-Lib nicht verfügbar, weitermachen
                    }
                    continue
                }
                
                $context = $contextTask.Result
                $request = $context.Request
                $response = $context.Response
                
                Write-Verbose "Request: $($request.HttpMethod) $($request.Url.AbsolutePath)"
                
                # Request-Handler aufrufen
                if ($RequestHandler) {
                    # Custom-Handler
                    & $RequestHandler $context
                } else {
                    # Router verwenden (falls verfügbar)
                    try {
                        Invoke-FVRoute -Request $request -Response $response -ErrorAction Stop
                    } catch {
                        # Router nicht verfügbar oder Route nicht gefunden
                        Write-Verbose "Router-Fehler: $($_.Exception.Message)"
                        
                        # Fallback: 404
                        $html = "<h1>404 - Not Found</h1><p>$($request.Url.AbsolutePath)</p>"
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                        $response.StatusCode = 404
                        $response.ContentType = "text/html; charset=utf-8"
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        $response.Close()
                    }
                }
                
            } catch [System.Net.HttpListenerException] {
                # Listener wurde gestoppt → Loop beenden
                Write-Verbose "HttpListener gestoppt"
                break
            } catch {
                Write-FVLog -Level Error -Message "Request-Fehler: $($_.Exception.Message)" -Exception $_
                
                # Versuche 500-Response zu senden
                try {
                    if ($null -ne $response -and -not $response.OutputStream.CanWrite) {
                        $html = "<h1>500 - Internal Server Error</h1>"
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                        $response.StatusCode = 500
                        $response.ContentType = "text/html; charset=utf-8"
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        $response.Close()
                    }
                } catch {
                    Write-Verbose "Konnte keine Error-Response senden"
                }
            }
        }
        
        # Cleanup
        Write-FVLog -Level Info -Message "HTTP-Server wird beendet..."
        Stop-FVHttpServer
        
    } catch {
        Write-FVLog -Level Error -Message "Fehler beim Starten des Servers: $($_.Exception.Message)" -Exception $_
        
        # Cleanup bei Fehler
        if ($null -ne $script:FVHttpListener) {
            try {
                $script:FVHttpListener.Stop()
                $script:FVHttpListener.Close()
            } catch {
                Write-Verbose "Cleanup-Fehler: $($_.Exception.Message)"
            }
        }
        
        $script:FVHttpRunning = $false
        throw
    }
}

function Stop-FVHttpServer {
    <#
    .SYNOPSIS
    Stoppt HTTP-Server
    
    .DESCRIPTION
    Stoppt den HttpListener sauber.
    Schließt alle offenen Verbindungen.
    
    Wird automatisch aufgerufen wenn Server-Loop endet.
    Kann auch manuell aufgerufen werden.
    
    .EXAMPLE
    Stop-FVHttpServer
    
    .EXAMPLE
    # Mit Verbose-Output
    Stop-FVHttpServer -Verbose
    
    .NOTES
    Setzt ServerRunning-State auf $false (falls State-Lib verfügbar).
    Ruft Garbage Collection auf für sauberes Cleanup.
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        if (-not $script:FVHttpRunning) {
            Write-Verbose "Server läuft nicht"
            return
        }
        
        Write-Verbose "Stoppe HTTP-Server..."
        
        # State setzen (Loop beenden)
        $script:FVHttpRunning = $false
        
        try {
            Set-FVState -Key "ServerRunning" -Value $false -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "State-Lib nicht verfügbar (OK)"
        }
        
        # Listener stoppen
        if ($null -ne $script:FVHttpListener) {
            try {
                $script:FVHttpListener.Stop()
                $script:FVHttpListener.Close()
                Write-Verbose "HttpListener gestoppt"
            } catch {
                Write-Verbose "Fehler beim Stoppen: $($_.Exception.Message)"
            }
            
            $script:FVHttpListener = $null
        }
        
        # Garbage Collection (File-Handles freigeben)
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        
        Write-FVLog -Level Info -Message "HTTP-Server gestoppt"
        
    } catch {
        Write-FVLog -Level Error -Message "Fehler beim Stoppen des Servers: $($_.Exception.Message)" -Exception $_
        throw
    }
}

function Get-FVHttpServerStatus {
    <#
    .SYNOPSIS
    Gibt Server-Status zurück
    
    .DESCRIPTION
    Prüft ob Server läuft und gibt Status-Informationen zurück.
    
    .EXAMPLE
    $status = Get-FVHttpServerStatus
    if ($status.Running) {
        Write-Host "Server läuft auf Port $($status.Port)"
    }
    
    .EXAMPLE
    Get-FVHttpServerStatus | Format-List
    
    .OUTPUTS
    PSCustomObject mit Status-Informationen:
    - Running: Boolean
    - Prefixes: String[]
    - IsListening: Boolean
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        $status = [PSCustomObject]@{
            Running = $script:FVHttpRunning
            Prefixes = @()
            IsListening = $false
        }
        
        if ($null -ne $script:FVHttpListener) {
            $status.Prefixes = @($script:FVHttpListener.Prefixes)
            $status.IsListening = $script:FVHttpListener.IsListening
        }
        
        return $status
        
    } catch {
        Write-Error "Fehler beim Abrufen des Server-Status: $($_.Exception.Message)"
        throw
    }
}