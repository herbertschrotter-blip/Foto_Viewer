<#
.SYNOPSIS
HTTP-Router für Foto_Viewer

.DESCRIPTION
Verwaltet Routen und leitet Requests an passende Handler weiter.
Unterstützt Pattern-Matching und Wildcards.

Funktionen:
- Register-FVRoute: Route mit Handler registrieren
- Invoke-FVRoute: Request an passenden Handler weiterleiten
- Get-FVRoutes: Alle registrierten Routen auflisten
- Clear-FVRoutes: Alle Routen löschen

Route-Matching:
- Exakt: "/api/img" → nur "/api/img"
- Wildcard: "/api/*" → "/api/img", "/api/video", etc.
- Trailing Slash wird ignoriert: "/api" = "/api/"

.EXAMPLE
# Route registrieren
Register-FVRoute -Path "/" -Method GET -Handler {
    param($Request, $Response)
    Send-FVHtmlResponse -Response $Response -Html "<h1>Home</h1>"
}

# Route mit Wildcard
Register-FVRoute -Path "/api/*" -Method GET -Handler {
    param($Request, $Response)
    # Behandelt alle /api/* Requests
}

# Request routen
Invoke-FVRoute -Request $request -Response $response

.NOTES
Autor: Herbert Schrotter
Version: 1.0.0
Erstellt: 2025-02-18
Projekt: Foto_Viewer

Matching-Reihenfolge:
1. Exakte Matches zuerst
2. Wildcards nach Spezifität (längster Match zuerst)
3. 404 wenn keine Route matched

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

$script:FVRoutes = @()

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

function Test-RouteMatch {
    <#
    .SYNOPSIS
    Prüft ob Request-Pfad zu Route passt
    
    .DESCRIPTION
    Vergleicht Request-Pfad mit Route-Pattern.
    Unterstützt Wildcards (*).
    
    .PARAMETER RequestPath
    Request-Pfad (z.B. "/api/img")
    
    .PARAMETER RoutePath
    Route-Pattern (z.B. "/api/*")
    
    .EXAMPLE
    Test-RouteMatch -RequestPath "/api/img" -RoutePath "/api/*"
    # → $true
    
    .EXAMPLE
    Test-RouteMatch -RequestPath "/api/img" -RoutePath "/video"
    # → $false
    
    .OUTPUTS
    Boolean
    
    .NOTES
    Internal Helper
    #>
    
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$RequestPath,
        
        [Parameter(Mandatory)]
        [string]$RoutePath
    )
    
    try {
        # Trailing Slash normalisieren
        $RequestPath = $RequestPath.TrimEnd('/')
        $RoutePath = $RoutePath.TrimEnd('/')
        
        if ([string]::IsNullOrEmpty($RequestPath)) { $RequestPath = "/" }
        if ([string]::IsNullOrEmpty($RoutePath)) { $RoutePath = "/" }
        
        # Exakter Match?
        if ($RequestPath -eq $RoutePath) {
            return $true
        }
        
        # Wildcard-Match?
        if ($RoutePath -like "*`*") {
            # Route-Pattern in Regex umwandeln
            # Escape special regex chars außer *
            $pattern = [regex]::Escape($RoutePath) -replace '\\\*', '.*'
            $pattern = "^$pattern$"
            
            if ($RequestPath -match $pattern) {
                return $true
            }
        }
        
        return $false
        
    } catch {
        Write-Verbose "Route-Match-Fehler: $($_.Exception.Message)"
        return $false
    }
}

function Get-RouteMatchScore {
    <#
    .SYNOPSIS
    Berechnet Match-Score für Route-Sortierung
    
    .DESCRIPTION
    Höhere Scores = spezifischere Routes (zuerst matchen).
    
    Score-Berechnung:
    - Exakt: Länge des Pfads * 1000
    - Wildcard: Länge bis Wildcard * 100
    
    .PARAMETER RoutePath
    Route-Pattern
    
    .EXAMPLE
    Get-RouteMatchScore -RoutePath "/api/img"
    # → 8000 (exakt, 8 Zeichen)
    
    .EXAMPLE
    Get-RouteMatchScore -RoutePath "/api/*"
    # → 500 (wildcard, 5 Zeichen bis *)
    
    .OUTPUTS
    Int32 - Score
    
    .NOTES
    Internal Helper
    #>
    
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$RoutePath
    )
    
    try {
        if ($RoutePath -notlike "*`*") {
            # Exakt: Höchste Priorität
            return $RoutePath.Length * 1000
        } else {
            # Wildcard: Nach Spezifität
            $beforeWildcard = $RoutePath -replace '\*.*$', ''
            return $beforeWildcard.Length * 100
        }
        
    } catch {
        return 0
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Register-FVRoute {
    <#
    .SYNOPSIS
    Registriert eine Route
    
    .DESCRIPTION
    Fügt Route mit Handler zur Routing-Tabelle hinzu.
    
    Routes werden nach Spezifität sortiert:
    1. Exakte Matches (z.B. "/api/img")
    2. Spezifische Wildcards (z.B. "/api/video/*")
    3. Allgemeine Wildcards (z.B. "/api/*")
    
    .PARAMETER Path
    Route-Pfad (z.B. "/" oder "/api/img" oder "/api/*")
    
    Wildcards:
    - "*" matched alles: "/api/*" matched "/api/img", "/api/video", etc.
    - Trailing Slash optional: "/api" = "/api/"
    
    .PARAMETER Method
    HTTP-Methode: GET, POST, PUT, DELETE, etc.
    
    .PARAMETER Handler
    ScriptBlock der ausgeführt wird wenn Route matched.
    
    Bekommt 2 Parameter:
    - $Request: HttpListenerRequest
    - $Response: HttpListenerResponse
    
    .EXAMPLE
    Register-FVRoute -Path "/" -Method GET -Handler {
        param($Request, $Response)
        Send-FVHtmlResponse -Response $Response -Html "<h1>Home</h1>"
    }
    
    .EXAMPLE
    # Wildcard für alle API-Routen
    Register-FVRoute -Path "/api/*" -Method GET -Handler {
        param($Request, $Response)
        $path = $Request.Url.AbsolutePath
        Write-FVLog -Level Info -Message "API Request: $path"
        # ... Handler-Logic
    }
    
    .EXAMPLE
    # POST-Route
    Register-FVRoute -Path "/api/delete" -Method POST -Handler {
        param($Request, $Response)
        $body = Read-FVRequestBody -Request $Request
        # ... Delete-Logic
    }
    
    .NOTES
    Routes mit gleichem Path+Method werden überschrieben (Last-Wins).
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyString()]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS', 'PATCH')]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock]$Handler
    )
    
    try {
        # Trailing Slash normalisieren
        $Path = $Path.TrimEnd('/')
        if ([string]::IsNullOrEmpty($Path)) { $Path = "/" }
        
        # Prüfen ob Route bereits existiert
        $existing = $script:FVRoutes | Where-Object { 
            $_.Path -eq $Path -and $_.Method -eq $Method 
        }
        
        if ($existing) {
            Write-Verbose "Route existiert bereits, überschreibe: $Method $Path"
            $script:FVRoutes = @($script:FVRoutes | Where-Object { 
                -not ($_.Path -eq $Path -and $_.Method -eq $Method)
            })
        }
        
        # Route hinzufügen
        $score = Get-RouteMatchScore -RoutePath $Path
        
        $route = [PSCustomObject]@{
            Path = $Path
            Method = $Method
            Handler = $Handler
            Score = $score
        }
        
        $script:FVRoutes += $route
        
        # Nach Score sortieren (höchste zuerst)
        $script:FVRoutes = @($script:FVRoutes | Sort-Object Score -Descending)
        
        Write-Verbose "Route registriert: $Method $Path (Score: $score)"
        
    } catch {
        Write-Error "Fehler beim Registrieren der Route: $($_.Exception.Message)"
        throw
    }
}

function Invoke-FVRoute {
    <#
    .SYNOPSIS
    Routet Request an passenden Handler
    
    .DESCRIPTION
    Sucht passende Route für Request und ruft Handler auf.
    
    Matching-Reihenfolge:
    1. Exakte Matches nach Method + Path
    2. Wildcard-Matches nach Spezifität
    3. 404 wenn keine Route matched
    
    .PARAMETER Request
    HttpListenerRequest-Objekt
    
    .PARAMETER Response
    HttpListenerResponse-Objekt
    
    .EXAMPLE
    # Im HttpServer Request-Loop:
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    
    Invoke-FVRoute -Request $request -Response $response
    
    .EXAMPLE
    # Mit Verbose für Debugging
    Invoke-FVRoute -Request $request -Response $response -Verbose
    
    .NOTES
    Wirft Exception wenn:
    - Handler fehlschlägt
    - Response bereits geschlossen
    
    Sendet automatisch 404 wenn keine Route matched.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerRequest]$Request,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerResponse]$Response
    )
    
    try {
        $method = $Request.HttpMethod
        $path = $Request.Url.AbsolutePath
        
        Write-Verbose "Route-Suche: $method $path"
        
        # Passende Route suchen (bereits nach Score sortiert)
        $matchedRoute = $null
        
        foreach ($route in $script:FVRoutes) {
            # Method-Check
            if ($route.Method -ne $method) {
                continue
            }
            
            # Path-Check
            if (Test-RouteMatch -RequestPath $path -RoutePath $route.Path) {
                $matchedRoute = $route
                Write-Verbose "Route matched: $($route.Method) $($route.Path) (Score: $($route.Score))"
                break
            }
        }
        
        # Route gefunden?
        if ($null -ne $matchedRoute) {
            # Handler aufrufen
            try {
                & $matchedRoute.Handler $Request $Response
                Write-Verbose "Handler erfolgreich ausgeführt"
                
            } catch {
                Write-FVLog -Level Error -Message "Handler-Fehler für $method $path : $($_.Exception.Message)" -Exception $_
                
                # 500-Response senden (falls noch möglich)
                try {
                    if (-not $Response.OutputStream.CanWrite) {
                        throw "Response bereits geschlossen"
                    }
                    
                    $html = @"
<!DOCTYPE html>
<html>
<head><title>500 - Internal Server Error</title></head>
<body style="font-family: Arial; padding: 50px; background: #1a1a1a; color: #fff;">
    <h1 style="color: #f44336;">500 - Internal Server Error</h1>
    <p>Ein Fehler ist aufgetreten beim Verarbeiten des Requests.</p>
    <p><strong>Path:</strong> $path</p>
    <p><strong>Error:</strong> $($_.Exception.Message)</p>
</body>
</html>
"@
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                    $Response.StatusCode = 500
                    $Response.ContentType = "text/html; charset=utf-8"
                    $Response.ContentLength64 = $buffer.Length
                    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $Response.Close()
                    
                } catch {
                    Write-Verbose "Konnte keine 500-Response senden: $($_.Exception.Message)"
                }
                
                throw
            }
            
        } else {
            # Keine Route gefunden → 404
            Write-Verbose "Keine Route gefunden für: $method $path"
            
            $html = @"
<!DOCTYPE html>
<html>
<head><title>404 - Not Found</title></head>
<body style="font-family: Arial; padding: 50px; background: #1a1a1a; color: #fff;">
    <h1 style="color: #ff9800;">404 - Not Found</h1>
    <p>Die angeforderte Ressource wurde nicht gefunden.</p>
    <p><strong>Path:</strong> $path</p>
    <p><strong>Method:</strong> $method</p>
</body>
</html>
"@
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
            $Response.StatusCode = 404
            $Response.ContentType = "text/html; charset=utf-8"
            $Response.ContentLength64 = $buffer.Length
            $Response.OutputStream.Write($buffer, 0, $buffer.Length)
            $Response.Close()
        }
        
    } catch {
        Write-Error "Fehler beim Routen: $($_.Exception.Message)"
        throw
    }
}

function Get-FVRoutes {
    <#
    .SYNOPSIS
    Listet alle registrierten Routen auf
    
    .DESCRIPTION
    Gibt Array aller Routen zurück (sortiert nach Score).
    Nützlich für Debugging.
    
    .EXAMPLE
    $routes = Get-FVRoutes
    $routes | Format-Table Path, Method, Score
    
    .EXAMPLE
    Get-FVRoutes | ForEach-Object {
        Write-Host "$($_.Method) $($_.Path) (Score: $($_.Score))"
    }
    
    .OUTPUTS
    PSCustomObject[] - Array von Routen
    
    Properties:
    - Path: String
    - Method: String
    - Handler: ScriptBlock
    - Score: Int32
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()
    
    try {
        Write-Verbose "Registrierte Routen: $($script:FVRoutes.Count)"
        return @($script:FVRoutes)
        
    } catch {
        Write-Error "Fehler beim Abrufen der Routen: $($_.Exception.Message)"
        throw
    }
}

function Clear-FVRoutes {
    <#
    .SYNOPSIS
    Löscht alle Routen
    
    .DESCRIPTION
    Entfernt alle registrierten Routen aus der Routing-Tabelle.
    Nützlich für Tests oder komplettes Neu-Setup.
    
    .EXAMPLE
    Clear-FVRoutes
    
    .EXAMPLE
    Clear-FVRoutes -Verbose
    
    .NOTES
    WARNUNG: Alle Handler gehen verloren!
    Server kann keine Requests mehr routen bis neue Routes registriert werden.
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        $count = $script:FVRoutes.Count
        $script:FVRoutes = @()
        Write-Verbose "Alle Routen gelöscht (vorher: $count)"
        
    } catch {
        Write-Error "Fehler beim Löschen der Routen: $($_.Exception.Message)"
        throw
    }
}