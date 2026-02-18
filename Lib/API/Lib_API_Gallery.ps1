<#
.SYNOPSIS
Gallery API-Handler für Foto_Viewer

.DESCRIPTION
Registriert Routes für Gallery-Funktionalität:
- GET / → Gallery-Seite (HTML)
- GET /api/media → Media-Liste (JSON)

Verwendet:
- Lib_Scanner (Medien scannen)
- Lib_Thumbnails (Thumbnails generieren)
- Lib_TemplateEngine (HTML rendern)
- Lib_Response (Responses senden)

.EXAMPLE
# In start.ps1:
Register-FVGalleryRoutes

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

function Register-FVGalleryRoutes {
    <#
    .SYNOPSIS
    Registriert Gallery-Routes
    
    .DESCRIPTION
    Registriert folgende Routes:
    - GET / → Gallery-Seite
    - GET /api/media → Media-Liste als JSON
    
    .EXAMPLE
    Register-FVGalleryRoutes
    
    .NOTES
    Verwendet Router aus Lib_Router.ps1
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Registriere Gallery-Routes..."
        
        # Route: GET /
        Register-FVRoute -Path "/" -Method GET -Handler {
            param($Request, $Response)
            
            try {
                Write-Verbose "Handler: GET /"
                
                # Root-Path aus State
                $rootPath = Get-FVState -Key "RootPath"
                
                if (-not $rootPath -or -not (Test-Path -LiteralPath $rootPath)) {
                    # Kein Root-Path → Zeige Setup-Seite
                    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Foto Viewer - Setup</title>
    <style>
        body { 
            font-family: Arial; 
            background: #0f172a; 
            color: #f1f5f9; 
            display: flex; 
            align-items: center; 
            justify-content: center; 
            height: 100vh; 
            margin: 0; 
        }
        .setup { 
            text-align: center; 
            max-width: 600px; 
            padding: 2rem; 
        }
        h1 { color: #2563eb; }
        p { margin: 1rem 0; }
        .code { 
            background: #1e293b; 
            padding: 1rem; 
            border-radius: 0.5rem; 
            margin: 1rem 0; 
            font-family: monospace; 
        }
    </style>
</head>
<body>
    <div class="setup">
        <h1>🚀 Foto Viewer Setup</h1>
        <p>Willkommen! Bitte konfiguriere zuerst den Medien-Pfad:</p>
        <div class="code">
            Set-FVState -Key "RootPath" -Value "C:\Dein\Foto\Ordner"
        </div>
        <p>Dann neu laden: <a href="/" style="color: #2563eb;">Refresh</a></p>
    </div>
</body>
</html>
"@
                    Send-FVHtmlResponse -Response $Response -Html $html
                    return
                }
                
                # Medien scannen
                Write-Verbose "Scanne Medien: $rootPath"
                $media = Invoke-FVScan -Path $rootPath -Recursive $true
                
                # Thumbnails generieren (async in Background)
                $thumbnailJobs = @()
                foreach ($item in $media) {
                    # Cache-Check
                    if (-not (Test-FVThumbnailCache -MediaPath $item.Path)) {
                        # Thumbnail fehlt → Generieren
                        Write-Verbose "Generiere Thumbnail: $($item.Name)"
                        try {
                            New-FVThumbnail -MediaPath $item.Path -ErrorAction SilentlyContinue | Out-Null
                        } catch {
                            Write-Verbose "Thumbnail-Fehler: $($_.Exception.Message)"
                        }
                    }
                }
                
                # Statistiken
                $imageCount = @($media | Where-Object Type -eq 'Image').Count
                $videoCount = @($media | Where-Object Type -eq 'Video').Count
                $totalSize = ($media | Measure-Object -Property Size -Sum).Sum
                
                # Template-Daten vorbereiten
                $mediaItems = $media | ForEach-Object {
                    $item = $_
                    
                    # Thumbnail-Pfade
                    $thumbs = @()
                    if ($item.Type -eq 'Video') {
                        # Multi-Frame Video-Thumbs
                        $config = Read-FVConfig
                        $frameCount = if ($config.Thumbnails.VideoFrames) { $config.Thumbnails.VideoFrames } else { 3 }
                        
                        for ($i = 1; $i -le $frameCount; $i++) {
                            $thumbPath = Get-FVThumbnailPath -MediaPath $item.Path -FrameIndex $i
                            if (Test-Path -LiteralPath $thumbPath) {
                                $relativePath = $thumbPath.Replace($rootPath, '').TrimStart('\', '/')
                                $thumbs += "/media/$relativePath"
                            }
                        }
                    } else {
                        # Single Image Thumb
                        $thumbPath = Get-FVThumbnailPath -MediaPath $item.Path
                        if (Test-Path -LiteralPath $thumbPath) {
                            $relativePath = $thumbPath.Replace($rootPath, '').TrimStart('\', '/')
                            $thumbs += "/media/$relativePath"
                        }
                    }
                    
                    # Media-Pfad relativ
                    $mediaRelativePath = $item.Path.Replace($rootPath, '').TrimStart('\', '/')
                    
                    @{
                        name = $item.Name
                        path = "/media/$mediaRelativePath"
                        type = $item.Type
                        size = $item.Size
                        thumbs = $thumbs
                    }
                }
                
                # Template rendern
                $templateData = @{
                    title = "Gallery"
                    imageCount = $imageCount
                    videoCount = $videoCount
                    totalSize = "{0:N2} GB" -f ($totalSize / 1GB)
                    mediaItems = $mediaItems
                    cssUrl = Get-FVAssetUrl -Path "css/style.css" -WithCacheBust
                    jsUrl = Get-FVAssetUrl -Path "js/app.js" -WithCacheBust
                }
                
                $html = Invoke-FVTemplate -Name "gallery" -Data $templateData
                
                # Response senden
                Send-FVHtmlResponse -Response $Response -Html $html
                
                Write-Verbose "Gallery gerendert: $($media.Count) Medien"
                
            } catch {
                Write-Error "Fehler in Gallery-Handler: $($_.Exception.Message)"
                Send-FVErrorResponse -Response $Response -StatusCode 500 -Message "Gallery-Fehler" -Details $_.Exception.Message
            }
        }
        
        # Route: GET /api/media
        Register-FVRoute -Path "/api/media" -Method GET -Handler {
            param($Request, $Response)
            
            try {
                Write-Verbose "Handler: GET /api/media"
                
                # Root-Path
                $rootPath = Get-FVState -Key "RootPath"
                
                if (-not $rootPath) {
                    Send-FVJsonResponse -Response $Response -Data @{ 
                        error = "Root-Path nicht konfiguriert"
                    } -StatusCode 400
                    return
                }
                
                # Query-Parameter
                $type = Get-FVQueryParam -Request $Request -Name "type" -Default "all"
                $sortBy = Get-FVQueryParam -Request $Request -Name "sort" -Default "name"
                
                # Medien scannen
                $typeFilter = switch ($type) {
                    'images' { 'Images' }
                    'videos' { 'Videos' }
                    default { 'All' }
                }
                
                $media = Invoke-FVScan -Path $rootPath -Type $typeFilter -Recursive $true -SortBy Name
                
                # JSON vorbereiten
                $mediaJson = $media | ForEach-Object {
                    @{
                        name = $_.Name
                        path = $_.RelativePath
                        type = $_.Type
                        size = $_.Size
                        modified = $_.LastModified.ToString('o')
                    }
                }
                
                # Response
                Send-FVJsonResponse -Response $Response -Data @{
                    count = $media.Count
                    items = $mediaJson
                }
                
                Write-Verbose "API: $($media.Count) Medien geliefert"
                
            } catch {
                Write-Error "Fehler in Media-API: $($_.Exception.Message)"
                Send-FVJsonResponse -Response $Response -Data @{ 
                    error = $_.Exception.Message 
                } -StatusCode 500
            }
        }
        
        Write-Verbose "Gallery-Routes registriert"
        
    } catch {
        Write-Error "Fehler beim Registrieren der Gallery-Routes: $($_.Exception.Message)"
        throw
    }
}