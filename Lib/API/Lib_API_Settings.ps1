<#
.SYNOPSIS
Settings API-Handler für Foto_Viewer

.DESCRIPTION
Registriert Routes für Settings-Funktionalität:
- GET /settings → Settings-Seite
- POST /api/settings → Settings speichern
- POST /api/settings/reset → Zurücksetzen
- GET /api/browse-folder → Ordner-Dialog

.NOTES
Autor: Herbert Schrotter
Version: 1.0.0
Erstellt: 2025-02-18
Projekt: Foto_Viewer
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

function Register-FVSettingsRoutes {
    <#
    .SYNOPSIS
    Registriert Settings-Routes
    
    .DESCRIPTION
    Registriert:
    - GET /settings → Settings-Seite
    - POST /api/settings → Speichern
    - POST /api/settings/reset → Reset
    - GET /api/browse-folder → Ordner wählen
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Registriere Settings-Routes..."
        
        # ====================================================================
        # Route: GET /settings
        # ====================================================================
        Register-FVRoute -Path "/settings" -Method GET -Handler {
            param($Request, $Response)
            
            try {
                Write-Verbose "Handler: GET /settings"
                
                # Config laden
                $config = Read-FVConfig
                $rootPath = Get-FVState -Key "RootPath"
                
                # Template-Daten
                $data = @{
                    rootPath = if ($rootPath) { $rootPath } else { "Nicht konfiguriert" }
                    port = $config.Server.Port
                    thumbSize = $config.Thumbnails.Size
                    thumbQuality = $config.Thumbnails.Quality
                    videoFrames = $config.Thumbnails.VideoFrames
                    # Quality-Selected
                    qualityLow = if ($config.Thumbnails.Quality -eq 3) { 'selected' } else { '' }
                    qualityMedium = if ($config.Thumbnails.Quality -eq 5) { 'selected' } else { '' }
                    qualityHigh = if ($config.Thumbnails.Quality -eq 8) { 'selected' } else { '' }
                }
                
                # Template rendern
                $html = Invoke-FVTemplate -Name "settings" -Data $data
                
                # Response
                Send-FVHtmlResponse -Response $Response -Html $html
                
            } catch {
                Write-Error "Fehler in Settings-Handler: $($_.Exception.Message)"
                Send-FVErrorResponse -Response $Response -StatusCode 500 -Message "Settings-Fehler"
            }
        }
        
        # ====================================================================
        # Route: POST /api/settings
        # ====================================================================
        Register-FVRoute -Path "/api/settings" -Method POST -Handler {
            param($Request, $Response)
            
            try {
                Write-Verbose "Handler: POST /api/settings"
                
                # Body lesen
                $body = Read-FVRequestBody -Request $Request
                $settings = $body | ConvertFrom-Json
                
                Write-Verbose "Settings: $($settings | ConvertTo-Json)"
                
                # Config laden
                $configPath = Join-Path $PSScriptRoot "..\..\config\settings.json"
                $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                
                # Änderungen anwenden
                $needsRestart = $false
                
                # Root-Path
                if ($settings.rootPath -and (Test-Path -LiteralPath $settings.rootPath)) {
                    Set-FVState -Key "RootPath" -Value $settings.rootPath
                    Write-Verbose "RootPath gesetzt: $($settings.rootPath)"
                }
                
                # Port (erfordert Neustart)
                if ($settings.port -ne $config.Server.Port) {
                    $config.Server.Port = $settings.port
                    $needsRestart = $true
                }
                
                # Thumbnails
                $config.Thumbnails.Size = $settings.thumbSize
                $config.Thumbnails.Quality = $settings.thumbQuality
                $config.Thumbnails.VideoFrames = $settings.videoFrames
                
                # Config speichern
                $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
                
                Write-Verbose "Config gespeichert"
                
                # Response
                Send-FVJsonResponse -Response $Response -Data @{
                    success = $true
                    needsRestart = $needsRestart
                    message = if ($needsRestart) { "Server-Neustart erforderlich" } else { "Einstellungen gespeichert" }
                }
                
            } catch {
                Write-Error "Fehler beim Speichern: $($_.Exception.Message)"
                Send-FVJsonResponse -Response $Response -Data @{ 
                    success = $false
                    error = $_.Exception.Message 
                } -StatusCode 500
            }
        }
        
        # ====================================================================
        # Route: POST /api/settings/reset
        # ====================================================================
        Register-FVRoute -Path "/api/settings/reset" -Method POST -Handler {
            param($Request, $Response)
            
            try {
                Write-Verbose "Handler: POST /api/settings/reset"
                
                # Default Config
                $defaultConfig = @{
                    Server = @{
                        Port = 8787
                        Host = "localhost"
                    }
                    Thumbnails = @{
                        Size = 140
                        Quality = 5
                        VideoFrames = 3
                        VideoFrameRangeStart = 0.2
                        VideoFrameRangeEnd = 0.9
                    }
                    MediaExtensions = @{
                        Images = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp")
                        Videos = @(".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v", ".mpg", ".mpeg")
                    }
                }
                
                # Speichern
                $configPath = Join-Path $PSScriptRoot "..\..\config\settings.json"
                $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
                
                Write-Verbose "Config auf Standard zurückgesetzt"
                
                # Response
                Send-FVJsonResponse -Response $Response -Data @{
                    success = $true
                    message = "Auf Standard zurückgesetzt"
                }
                
            } catch {
                Write-Error "Fehler beim Reset: $($_.Exception.Message)"
                Send-FVJsonResponse -Response $Response -Data @{ 
                    success = $false
                    error = $_.Exception.Message 
                } -StatusCode 500
            }
        }
        
        # ====================================================================
        # Route: GET /api/browse-folder
        # ====================================================================
        Register-FVRoute -Path "/api/browse-folder" -Method GET -Handler {
            param($Request, $Response)
            
            try {
                Write-Verbose "Handler: GET /api/browse-folder"
                
                # Folder-Browser Dialog
                Add-Type -AssemblyName System.Windows.Forms
                $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
                $folderBrowser.Description = "Wähle Medien-Ordner"
                $folderBrowser.RootFolder = [System.Environment+SpecialFolder]::MyComputer
                
                $result = $folderBrowser.ShowDialog()
                
                if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                    $selectedPath = $folderBrowser.SelectedPath
                    
                    Send-FVJsonResponse -Response $Response -Data @{
                        success = $true
                        path = $selectedPath
                    }
                } else {
                    Send-FVJsonResponse -Response $Response -Data @{
                        success = $false
                        path = $null
                    }
                }
                
            } catch {
                Write-Error "Fehler beim Ordner-Dialog: $($_.Exception.Message)"
                Send-FVJsonResponse -Response $Response -Data @{ 
                    success = $false
                    error = $_.Exception.Message 
                } -StatusCode 500
            }
        }
        
        Write-Verbose "Settings-Routes registriert"
        
    } catch {
        Write-Error "Fehler beim Registrieren der Settings-Routes: $($_.Exception.Message)"
        throw
    }
}