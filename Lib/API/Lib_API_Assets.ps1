<#
.SYNOPSIS
Asset-Serving API für Foto_Viewer

.DESCRIPTION
Serviert statische Assets:
- GET /assets/* → CSS, JS, Fonts
- GET /media/* → Fotos, Videos, Thumbnails

Features:
- Content-Type Detection
- Range-Requests für Videos
- Cache-Headers
- MIME-Type Support

.EXAMPLE
# In start.ps1:
Register-FVAssetRoutes

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
# PUBLIC FUNCTIONS
# ============================================================================

function Register-FVAssetRoutes {
    <#
    .SYNOPSIS
    Registriert Asset-Routes
    
    .DESCRIPTION
    Registriert folgende Routes:
    - GET /assets/* → Statische Assets (CSS/JS)
    - GET /media/* → Medien-Dateien (Fotos/Videos/Thumbs)
    
    .EXAMPLE
    Register-FVAssetRoutes
    
    .NOTES
    Verwendet Router aus Lib_Router.ps1
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Registriere Asset-Routes..."
        
        # Route: GET /assets/*
        Register-FVRoute -Path "/assets/*" -Method GET -Handler {
            param($Request, $Response)
            
            try {
                # Asset-Pfad extrahieren
                $requestPath = $Request.Url.LocalPath
                $assetPath = $requestPath -replace '^/assets/', ''
                
                Write-Verbose "Handler: GET /assets/$assetPath"
                
                # Projekt-Root ermitteln
                $scriptRoot = $PSScriptRoot
                $libDir = Split-Path $scriptRoot -Parent
                $projectRoot = Split-Path $libDir -Parent
                
                # Vollständiger Pfad
                $fullPath = Join-Path $projectRoot "templates\$assetPath"
                
                # Sicherheit: Path-Traversal verhindern
                $normalizedPath = [System.IO.Path]::GetFullPath($fullPath)
                $normalizedTemplateDir = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "templates"))
                
                if (-not $normalizedPath.StartsWith($normalizedTemplateDir)) {
                    Write-Verbose "Path-Traversal blockiert: $assetPath"
                    Send-FVErrorResponse -Response $Response -StatusCode 403 -Message "Forbidden"
                    return
                }
                
                # Datei existiert?
                if (-not (Test-Path -LiteralPath $fullPath)) {
                    Write-Verbose "Asset nicht gefunden: $assetPath"
                    Send-FVErrorResponse -Response $Response -StatusCode 404 -Message "Asset nicht gefunden"
                    return
                }
                
                # Datei servieren
                Write-Verbose "Serviere Asset: $assetPath"
                Send-FVFileResponse -Response $Response -FilePath $fullPath
                
            } catch {
                Write-Error "Fehler in Asset-Handler: $($_.Exception.Message)"
                Send-FVErrorResponse -Response $Response -StatusCode 500 -Message "Asset-Fehler"
            }
        }
        
        # Route: GET /media/*
        Register-FVRoute -Path "/media/*" -Method GET -Handler {
            param($Request, $Response)
            
            try {
                # Media-Pfad extrahieren
                $requestPath = $Request.Url.LocalPath
                $mediaPath = $requestPath -replace '^/media/', ''
                
                # URL-Dekodierung
                $mediaPath = ConvertFrom-FVUrlEncoded -Text $mediaPath
                
                Write-Verbose "Handler: GET /media/$mediaPath"
                
                # Root-Path aus State
                $rootPath = Get-FVState -Key "RootPath"
                
                if (-not $rootPath) {
                    Send-FVErrorResponse -Response $Response -StatusCode 500 -Message "Root-Path nicht konfiguriert"
                    return
                }
                
                # Vollständiger Pfad
                $fullPath = Join-Path $rootPath $mediaPath
                
                # Sicherheit: Path-Traversal verhindern
                $normalizedPath = [System.IO.Path]::GetFullPath($fullPath)
                $normalizedRootPath = [System.IO.Path]::GetFullPath($rootPath)
                
                if (-not $normalizedPath.StartsWith($normalizedRootPath)) {
                    Write-Verbose "Path-Traversal blockiert: $mediaPath"
                    Send-FVErrorResponse -Response $Response -StatusCode 403 -Message "Forbidden"
                    return
                }
                
                # Datei existiert?
                if (-not (Test-Path -LiteralPath $fullPath)) {
                    Write-Verbose "Media nicht gefunden: $mediaPath"
                    Send-FVErrorResponse -Response $Response -StatusCode 404 -Message "Datei nicht gefunden"
                    return
                }
                
                # Extension prüfen
                $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
                
                # Video? → Streaming mit Range-Support
                $videoExts = @('.mp4', '.avi', '.mkv', '.mov', '.wmv', '.webm', '.m4v')
                
                if ($ext -in $videoExts) {
                    Write-Verbose "Streaming Video: $mediaPath"
                    Send-FVStreamResponse -Response $Response -Request $Request -FilePath $fullPath
                } else {
                    Write-Verbose "Serviere Datei: $mediaPath"
                    Send-FVFileResponse -Response $Response -FilePath $fullPath
                }
                
            } catch {
                Write-Error "Fehler in Media-Handler: $($_.Exception.Message)"
                Send-FVErrorResponse -Response $Response -StatusCode 500 -Message "Media-Fehler"
            }
        }
        
        Write-Verbose "Asset-Routes registriert"
        
    } catch {
        Write-Error "Fehler beim Registrieren der Asset-Routes: $($_.Exception.Message)"
        throw
    }
}