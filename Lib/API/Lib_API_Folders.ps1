<#
.SYNOPSIS
Folder-Browser API für Foto_Viewer

.DESCRIPTION
Registriert API-Route für Ordner-Auswahl.
Ermöglicht Wechsel des Root-Path zur Laufzeit.

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

function Register-FVFolderRoutes {
    <#
    .SYNOPSIS
    Registriert Folder-Routes
    
    .DESCRIPTION
    Registriert:
    - POST /api/select-folder → Neuen Root-Path setzen
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Registriere Folder-Routes..."
        
        # ====================================================================
        # Route: POST /api/select-folder
        # ====================================================================
        Register-FVRoute -Path "/api/select-folder" -Method POST -Handler {
            param($Request, $Response)
            
            try {
                Write-Verbose "Handler: POST /api/select-folder"
                
                # Body lesen
                $body = Read-FVRequestBody -Request $Request
                $data = $body | ConvertFrom-Json
                
                $newPath = $data.path
                
                Write-Verbose "Neuer Pfad angefordert: $newPath"
                
                # Validierung
                if (-not $newPath) {
                    Send-FVJsonResponse -Response $Response -Data @{
                        success = $false
                        error = "Kein Pfad angegeben"
                    } -StatusCode 400
                    return
                }
                
                if (-not (Test-Path -LiteralPath $newPath -PathType Container)) {
                    Send-FVJsonResponse -Response $Response -Data @{
                        success = $false
                        error = "Pfad existiert nicht oder ist kein Ordner"
                    } -StatusCode 400
                    return
                }
                
                # Root-Path setzen
                Set-FVState -Key "RootPath" -Value $newPath
                
                Write-Verbose "Root-Path erfolgreich geändert: $newPath"
                
                # Response
                Send-FVJsonResponse -Response $Response -Data @{
                    success = $true
                    path = $newPath
                    message = "Ordner erfolgreich gewählt"
                }
                
            } catch {
                Write-Error "Fehler beim Setzen des Ordners: $($_.Exception.Message)"
                Send-FVJsonResponse -Response $Response -Data @{
                    success = $false
                    error = $_.Exception.Message
                } -StatusCode 500
            }
        }
        
        Write-Verbose "Folder-Routes registriert"
        
    } catch {
        Write-Error "Fehler beim Registrieren der Folder-Routes: $($_.Exception.Message)"
        throw
    }
}