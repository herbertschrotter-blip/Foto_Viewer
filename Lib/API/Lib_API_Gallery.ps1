<#
.SYNOPSIS
Gallery API-Handler für Foto_Viewer

.DESCRIPTION
Registriert Routes für Gallery-Funktionalität:
- GET / → Gallery-Seite (Ordner-Übersicht)
- GET /folder/* → Medien in spezifischem Ordner
- GET /api/media → Media-Liste (JSON)

.NOTES
Autor: Herbert Schrotter
Version: 1.1.0
Erstellt: 2025-02-18
Aktualisiert: 2025-02-18
Projekt: Foto_Viewer

Changelog:
- v1.1.0: Ordner-basierte Navigation mit Breadcrumbs
- v1.0.0: Initiale Version mit flacher Medien-Liste
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

function Register-FVGalleryRoutes {
    <#
    .SYNOPSIS
    Registriert Gallery-Routes
    
    .DESCRIPTION
    Registriert:
    - GET / → Gallery-Seite (Ordner-Übersicht)
    - GET /folder/* → Ordner-Inhalt mit Medien
    - GET /api/media → Media-Liste JSON
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Registriere Gallery-Routes..."
        
        # ====================================================================
        # Route: GET / (ORDNER-ÜBERSICHT)
        # ====================================================================
        Register-FVRoute -Path "/" -Method GET -Handler {
            param($Request, $Response)
            
            Write-Host "  → Gallery-Handler gestartet" -ForegroundColor Cyan
            
            try {
                Write-Verbose "Handler: GET / (Ordner-Übersicht)"
                
                # Root-Path aus State
                $rootPath = Get-FVState -Key "RootPath"
                
                Write-Host "    RootPath: $rootPath" -ForegroundColor Gray
                Write-Verbose "RootPath: $rootPath"
                
                if (-not $rootPath -or -not (Test-Path -LiteralPath $rootPath)) {
                    Write-Host "    → Setup-Seite (kein Root-Path)" -ForegroundColor Yellow
                    
                    # Setup-Seite
                    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Foto Viewer - Setup</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
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
            background: #1e293b;
            border-radius: 1rem;
        }
        h1 { color: #2563eb; margin-bottom: 1rem; }
        p { margin: 1rem 0; color: #94a3b8; }
        .code { 
            background: #0f172a; 
            padding: 1rem; 
            border-radius: 0.5rem; 
            margin: 1.5rem 0; 
            font-family: 'Consolas', monospace;
            font-size: 0.9rem;
            color: #10b981;
        }
        a { color: #2563eb; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="setup">
        <h1>🚀 Foto Viewer Setup</h1>
        <p>Willkommen! Bitte konfiguriere zuerst den Medien-Pfad:</p>
        <div class="code">
            Set-FVState -Key "RootPath" -Value "C:\Dein\Foto\Ordner"
        </div>
        <p>Dann neu laden: <a href="/">Refresh</a></p>
        <p style="font-size: 0.8rem; margin-top: 2rem; color: #64748b;">
            Hinweis: Führe den Befehl in PowerShell aus während der Server läuft.
        </p>
    </div>
</body>
</html>
"@
                    Send-FVHtmlResponse -Response $Response -Html $html
                    Write-Host "    ✓ Setup-Seite gesendet" -ForegroundColor Green
                    return
                }
                
                Write-Host "    → Scanne Ordner-Struktur..." -ForegroundColor Cyan
                
                # ORDNER-STRUKTUR statt flache Medien-Liste!
                $folders = @(Get-FVFolderStructure -Path $rootPath -Recursive $true)
                
                Write-Host "      Gefunden: $($folders.Count) Ordner" -ForegroundColor Gray
                Write-Verbose "Ordner gefunden: $($folders.Count)"
                
                # Config für Extensions
                $config = Read-FVConfig
                $imageExts = $config.MediaExtensions.Images
                $videoExts = $config.MediaExtensions.Videos
                $allExts = $imageExts + $videoExts
                
                # Für jeden Ordner: erste 10 Thumbnails sammeln
                Write-Host "    → Sammle Vorschau-Thumbnails..." -ForegroundColor Cyan
                
                $folderItems = @()
                $totalImages = 0
                $totalVideos = 0
                
                foreach ($folder in $folders) {
                    # Medien in diesem Ordner (NICHT rekursiv!)
                    $folderFiles = @(Get-ChildItem -LiteralPath $folder.Path -File -ErrorAction SilentlyContinue |
                        Where-Object { 
                            $_.Extension.ToLower() -in $allExts
                        } | Select-Object -First 10)
                    
                    if ($folderFiles.Count -eq 0) {
                        # Ordner ohne Medien überspringen
                        continue
                    }
                    
                    # Stats
                    $totalImages += $folder.ImageCount
                    $totalVideos += $folder.VideoCount
                    
                    # Thumbnail-URLs für Vorschau
                    $previewThumbs = @()
                    foreach ($file in $folderFiles) {
                        # Thumbnail generieren falls nicht vorhanden
                        if (-not (Test-FVThumbnailCache -MediaPath $file.FullName)) {
                            try {
                                New-FVThumbnail -MediaPath $file.FullName -ErrorAction SilentlyContinue | Out-Null
                            } catch {
                                # Ignorieren
                            }
                        }
                        
                        # Thumbnail-Pfad
                        $thumbPath = Get-FVThumbnailPath -MediaPath $file.FullName
                        if (Test-Path -LiteralPath $thumbPath) {
                            $thumbRelative = $thumbPath.Replace($rootPath, '').TrimStart('\', '/').Replace('\', '/')
                            $previewThumbs += "/media/$thumbRelative"
                        }
                    }
                    
                    # Ordner-Item erstellen
                    $folderItems += @{
                        name = $folder.Name
                        path = $folder.RelativePath
                        imageCount = $folder.ImageCount
                        videoCount = $folder.VideoCount
                        totalCount = $folder.TotalCount
                        previewThumbs = $previewThumbs
                    }
                }
                
                Write-Host "      Ordner mit Medien: $($folderItems.Count)" -ForegroundColor Gray
                Write-Host "      Gesamt: $totalImages Bilder, $totalVideos Videos" -ForegroundColor Gray
                
                # Template-Daten
                Write-Host "    → Rendere Template..." -ForegroundColor Cyan
                
                # Gesamt-Größe berechnen
                $allMedia = @(Invoke-FVScan -Path $rootPath -Recursive $true)
                $totalSize = ($allMedia | Measure-Object -Property Size -Sum).Sum
                
                $templateData = @{
                    title = 'Gallery - Ordner'
                    imageCount = $totalImages
                    videoCount = $totalVideos
                    totalSize = '{0:N2} GB' -f ($totalSize / 1GB)
                    folderItems = $folderItems
                    viewMode = 'folders'
                }
                
                # Template rendern
                $html = Invoke-FVTemplate -Name "gallery" -Data $templateData -NoCache
                
                Write-Host "    → Sende HTML..." -ForegroundColor Cyan
                
                # Response
                Send-FVHtmlResponse -Response $Response -Html $html
                
                Write-Host "    ✓ Gallery gesendet ($($html.Length) bytes)" -ForegroundColor Green
                Write-Verbose "Gallery gerendert: $($folderItems.Count) Ordner"
                
            } catch {
                Write-Host "    ✗ Fehler: $($_.Exception.Message)" -ForegroundColor Red
                Write-Error "Fehler in Gallery-Handler: $($_.Exception.Message)"
                Send-FVErrorResponse -Response $Response -StatusCode 500 -Message "Gallery-Fehler" -Details $_.Exception.Message
            }
        }
        
        # ====================================================================
        # Route: GET /folder/* (ORDNER-INHALT)
        # ====================================================================
        Register-FVRoute -Path "/folder/*" -Method GET -Handler {
            param($Request, $Response)
            
            Write-Host "  → Folder-View-Handler gestartet" -ForegroundColor Cyan
            
            try {
                # Relativen Pfad extrahieren
                $relativePath = $Request.Url.AbsolutePath -replace '^/folder/', ''
                $relativePath = [System.Web.HttpUtility]::UrlDecode($relativePath)
                
                Write-Verbose "Handler: GET /folder/$relativePath"
                Write-Host "    Ordner: $relativePath" -ForegroundColor Gray
                
                # Root-Path
                $rootPath = Get-FVState -Key "RootPath"
                
                if (-not $rootPath) {
                    Send-FVErrorResponse -Response $Response -StatusCode 400 -Message "Root-Path nicht gesetzt"
                    return
                }
                
                # Vollständiger Pfad
                $folderPath = Join-Path $rootPath $relativePath
                
                if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                    Send-FVErrorResponse -Response $Response -StatusCode 404 -Message "Ordner nicht gefunden"
                    return
                }
                
                Write-Host "    → Scanne Medien in Ordner..." -ForegroundColor Cyan
                
                # Medien NUR in diesem Ordner (NICHT rekursiv!)
                $media = @(Invoke-FVScan -Path $folderPath -Recursive $false)
                
                Write-Host "      Gefunden: $($media.Count) Dateien" -ForegroundColor Gray
                
                # Thumbnails generieren
                Write-Host "    → Generiere Thumbnails..." -ForegroundColor Cyan
                foreach ($item in $media) {
                    if (-not (Test-FVThumbnailCache -MediaPath $item.Path)) {
                        try {
                            New-FVThumbnail -MediaPath $item.Path -ErrorAction SilentlyContinue | Out-Null
                        } catch {
                            # Ignorieren
                        }
                    }
                }
                
                # Statistiken
                $imageCount = @($media | Where-Object Type -eq 'Image').Count
                $videoCount = @($media | Where-Object Type -eq 'Video').Count
                $totalSize = ($media | Measure-Object -Property Size -Sum).Sum
                
                # Media-Items für Template
                $mediaItems = $media | ForEach-Object {
                    $item = $_
                    
                    # Thumbnail-Pfade
                    $thumbs = @()
                    if ($item.Type -eq 'Video') {
                        # Multi-Frame
                        $config = Read-FVConfig
                        $frameCount = if ($config.Thumbnails.VideoFrames) { $config.Thumbnails.VideoFrames } else { 3 }
                        
                        for ($i = 1; $i -le $frameCount; $i++) {
                            $thumbPath = Get-FVThumbnailPath -MediaPath $item.Path -FrameIndex $i
                            if (Test-Path -LiteralPath $thumbPath) {
                                $thumbRelative = $thumbPath.Replace($rootPath, '').TrimStart('\', '/').Replace('\', '/')
                                $thumbs += "/media/$thumbRelative"
                            }
                        }
                    } else {
                        # Single
                        $thumbPath = Get-FVThumbnailPath -MediaPath $item.Path
                        if (Test-Path -LiteralPath $thumbPath) {
                            $thumbRelative = $thumbPath.Replace($rootPath, '').TrimStart('\', '/').Replace('\', '/')
                            $thumbs += "/media/$thumbRelative"
                        }
                    }
                    
                    # Media-Pfad
                    $mediaRelativePath = $item.Path.Replace($rootPath, '').TrimStart('\', '/').Replace('\', '/')
                    
                    @{
                        name = $item.Name
                        path = "/media/$mediaRelativePath"
                        type = $item.Type
                        size = $item.Size
                        thumbs = $thumbs
                    }
                }
                
                Write-Host "    → Rendere Template..." -ForegroundColor Cyan
                
                # Breadcrumb erstellen
                $breadcrumbs = @()
                $pathParts = $relativePath -split '[/\\]' | Where-Object { $_ }
                $currentPath = ''
                
                foreach ($part in $pathParts) {
                    $currentPath = if ($currentPath) { "$currentPath/$part" } else { $part }
                    $breadcrumbs += @{
                        name = $part
                        path = $currentPath
                    }
                }
                
                # Template-Daten
                $templateData = @{
                    title = "Ordner: $relativePath"
                    folderPath = $relativePath
                    breadcrumbs = $breadcrumbs
                    imageCount = $imageCount
                    videoCount = $videoCount
                    totalSize = '{0:N2} GB' -f ($totalSize / 1GB)
                    mediaItems = $mediaItems
                    viewMode = 'media'
                }
                
                # Template rendern (nutzt das normale gallery.html, viewMode unterscheidet)
                $html = Invoke-FVTemplate -Name "gallery" -Data $templateData
                
                Write-Host "    → Sende HTML..." -ForegroundColor Cyan
                
                # Response
                Send-FVHtmlResponse -Response $Response -Html $html
                
                Write-Host "    ✓ Folder-View gesendet ($($html.Length) bytes)" -ForegroundColor Green
                
            } catch {
                Write-Host "    ✗ Fehler: $($_.Exception.Message)" -ForegroundColor Red
                Write-Error "Fehler in Folder-View-Handler: $($_.Exception.Message)"
                Send-FVErrorResponse -Response $Response -StatusCode 500 -Message "Folder-View-Fehler" -Details $_.Exception.Message
            }
        }
        
        # ====================================================================
        # Route: GET /api/media
        # ====================================================================
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
                
                # JSON
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