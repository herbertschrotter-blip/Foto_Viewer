<#
.SYNOPSIS
Thumbnail-Generator für Foto_Viewer

.DESCRIPTION
Generiert Thumbnails für Bilder und Videos.
Verwendet FFmpeg für Videos, System.Drawing für Bilder.

Funktionen:
- New-FVThumbnail: Erstellt Thumbnail (Auto-Detect: Bild/Video)
- New-FVImageThumbnail: Erstellt Bild-Thumbnail
- New-FVVideoThumbnail: Erstellt Video-Thumbnail (FFmpeg)
- Get-FVThumbnailPath: Berechnet Cache-Pfad
- Test-FVThumbnailCache: Prüft ob Thumbnail existiert

Features:
- Intelligentes Caching (Hash-basiert)
- Konfigurierbare Größe aus Config
- JPEG-Qualität aus Config
- Aspect-Ratio-Erhaltung
- Parallel-Processing Support

.EXAMPLE
# Thumbnail erstellen
$thumbPath = New-FVThumbnail -MediaPath "C:\photo.jpg"
# → .thumbs/abc123.jpg

.EXAMPLE
# Video-Thumbnail
$thumbPath = New-FVThumbnail -MediaPath "C:\video.mp4"
# → .thumbs/def456.jpg (Frame bei 1 Sekunde)

.EXAMPLE
# Cache prüfen
if (Test-FVThumbnailCache -MediaPath "C:\photo.jpg") {
    $thumbPath = Get-FVThumbnailPath -MediaPath "C:\photo.jpg"
}

.NOTES
Autor: Herbert Schrotter
Version: 1.0.0
Erstellt: 2025-02-18
Projekt: Foto_Viewer

Benötigt:
- System.Drawing (für Bilder)
- FFmpeg (für Videos)

.LINK
https://github.com/herbertschrotter-blip/Foto_Viewer
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# System.Drawing laden (für Bild-Thumbnails)
Add-Type -AssemblyName System.Drawing

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

function Get-FFmpegPath {
    <#
    .SYNOPSIS
    Sucht FFmpeg.exe
    
    .DESCRIPTION
    Sucht in:
    1. Tools/ffmpeg/ffmpeg.exe (Projekt)
    2. $env:PATH (System)
    
    .OUTPUTS
    String - Pfad zu ffmpeg.exe
    
    .NOTES
    Internal Helper
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        # 1. Projekt-Tools
        $scriptRoot = $PSScriptRoot
        $libDir = Split-Path $scriptRoot -Parent
        $projectRoot = Split-Path $libDir -Parent
        $toolsPath = Join-Path $projectRoot "Tools\ffmpeg\ffmpeg.exe"
        
        if (Test-Path -LiteralPath $toolsPath) {
            Write-Verbose "FFmpeg gefunden: $toolsPath"
            return $toolsPath
        }
        
        # 2. System PATH
        $systemFFmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
        if ($systemFFmpeg) {
            Write-Verbose "FFmpeg gefunden in PATH: $($systemFFmpeg.Source)"
            return $systemFFmpeg.Source
        }
        
        throw "FFmpeg nicht gefunden. Bitte installiere FFmpeg in Tools/ffmpeg/ oder System PATH."
        
    } catch {
        Write-Error "Fehler beim Suchen von FFmpeg: $($_.Exception.Message)"
        throw
    }
}

function Get-FileHash256 {
    <#
    .SYNOPSIS
    Berechnet SHA256-Hash für Datei
    
    .DESCRIPTION
    Schneller Hash basierend auf Pfad + LastWriteTime + Size.
    Vermeidet komplette Datei zu lesen für bessere Performance.
    
    .PARAMETER FilePath
    Dateipfad
    
    .OUTPUTS
    String - Hex-Hash (16 Zeichen)
    
    .NOTES
    Internal Helper
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    try {
        $fileInfo = Get-Item -LiteralPath $FilePath -ErrorAction Stop
        
        # Hash aus Pfad + ModifiedDate + Size
        $hashInput = "$($fileInfo.FullName)|$($fileInfo.LastWriteTime.Ticks)|$($fileInfo.Length)"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
        
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($bytes)
        $sha256.Dispose()
        
        # Zu Hex (erste 16 Zeichen für kurzen Dateinamen)
        $hexHash = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLower().Substring(0, 16)
        
        return $hexHash
        
    } catch {
        Write-Error "Fehler beim Berechnen des File-Hash: $($_.Exception.Message)"
        throw
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Get-FVThumbnailPath {
    <#
    .SYNOPSIS
    Berechnet Thumbnail-Cache-Pfad
    
    .DESCRIPTION
    Gibt Pfad wo Thumbnail gespeichert wird/ist.
    Format: .thumbs/{hash}.jpg
    
    .PARAMETER MediaPath
    Pfad zur Medien-Datei
    
    .PARAMETER ThumbDirectory
    Optional: Thumbnail-Verzeichnis (Default: .thumbs)
    
    .EXAMPLE
    $thumbPath = Get-FVThumbnailPath -MediaPath "C:\photo.jpg"
    # → D:\...\03_Foto-Viewer\.thumbs\abc123.jpg
    
    .OUTPUTS
    String - Absoluter Pfad zum Thumbnail
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$MediaPath,
        
        [Parameter()]
        [string]$ThumbDirectory = ".thumbs"
    )
    
    try {
        # Projekt-Root
        $scriptRoot = $PSScriptRoot
        $libDir = Split-Path $scriptRoot -Parent
        $projectRoot = Split-Path $libDir -Parent
        
        # Thumbnail-Verzeichnis
        $thumbDir = Join-Path $projectRoot $ThumbDirectory
        
        # Hash berechnen
        $hash = Get-FileHash256 -FilePath $MediaPath
        
        # Thumbnail-Pfad
        $thumbPath = Join-Path $thumbDir "$hash.jpg"
        
        return $thumbPath
        
    } catch {
        Write-Error "Fehler beim Berechnen des Thumbnail-Pfads: $($_.Exception.Message)"
        throw
    }
}

function Test-FVThumbnailCache {
    <#
    .SYNOPSIS
    Prüft ob Thumbnail im Cache existiert
    
    .DESCRIPTION
    Gibt $true zurück wenn Thumbnail bereits generiert wurde.
    
    .PARAMETER MediaPath
    Pfad zur Medien-Datei
    
    .EXAMPLE
    if (Test-FVThumbnailCache -MediaPath "C:\photo.jpg") {
        Write-Host "Thumbnail existiert bereits"
    }
    
    .OUTPUTS
    Boolean
    #>
    
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$MediaPath
    )
    
    try {
        $thumbPath = Get-FVThumbnailPath -MediaPath $MediaPath
        return Test-Path -LiteralPath $thumbPath
        
    } catch {
        Write-Verbose "Fehler beim Prüfen des Thumbnail-Cache: $($_.Exception.Message)"
        return $false
    }
}

function New-FVImageThumbnail {
    <#
    .SYNOPSIS
    Erstellt Thumbnail für Bild
    
    .DESCRIPTION
    Verwendet System.Drawing für schnelle Thumbnail-Generierung.
    Erhält Aspect-Ratio.
    
    .PARAMETER ImagePath
    Pfad zum Bild
    
    .PARAMETER OutputPath
    Pfad für Thumbnail-Output
    
    .PARAMETER Size
    Optional: Max-Größe (Default: aus Config)
    
    .PARAMETER Quality
    Optional: JPEG-Qualität 1-10 (Default: aus Config)
    
    .EXAMPLE
    New-FVImageThumbnail -ImagePath "C:\photo.jpg" -OutputPath "C:\thumb.jpg"
    
    .EXAMPLE
    # Mit Custom-Size
    New-FVImageThumbnail -ImagePath "C:\photo.jpg" -OutputPath "C:\thumb.jpg" -Size 200 -Quality 8
    
    .NOTES
    Wirft Exception bei beschädigten Bildern
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$ImagePath,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [ValidateRange(16, 2048)]
        [int]$Size,
        
        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$Quality
    )
    
    try {
        # Config laden wenn Size/Quality nicht angegeben
        if (-not $Size -or -not $Quality) {
            $config = Read-FVConfig -ErrorAction Stop
            if (-not $Size) { $Size = $config.Thumbnails.Size }
            if (-not $Quality) { $Quality = $config.Thumbnails.Quality }
        }
        
        Write-Verbose "Erstelle Bild-Thumbnail: $ImagePath → $OutputPath (${Size}px, Q${Quality})"
        
        # Output-Verzeichnis erstellen
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Bild laden
        $image = [System.Drawing.Image]::FromFile($ImagePath)
        
        try {
            # Thumbnail-Größe berechnen (Aspect-Ratio erhalten)
            $ratio = $image.Width / $image.Height
            
            if ($ratio -gt 1) {
                # Landscape
                $thumbWidth = $Size
                $thumbHeight = [int]($Size / $ratio)
            } else {
                # Portrait
                $thumbWidth = [int]($Size * $ratio)
                $thumbHeight = $Size
            }
            
            Write-Verbose "Original: $($image.Width)x$($image.Height) → Thumbnail: ${thumbWidth}x${thumbHeight}"
            
            # Thumbnail erstellen
            $thumbnail = $image.GetThumbnailImage(
                $thumbWidth,
                $thumbHeight,
                $null,
                [IntPtr]::Zero
            )
            
            try {
                # JPEG-Encoder mit Qualität
                $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | 
                             Where-Object { $_.MimeType -eq 'image/jpeg' }
                
                $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                    [System.Drawing.Imaging.Encoder]::Quality,
                    [long]($Quality * 10)
                )
                
                # Speichern
                $thumbnail.Save($OutputPath, $jpegCodec, $encoderParams)
                
                Write-Verbose "Bild-Thumbnail erstellt: $OutputPath"
                
            } finally {
                $thumbnail.Dispose()
            }
            
        } finally {
            $image.Dispose()
        }
        
    } catch {
        Write-Error "Fehler beim Erstellen des Bild-Thumbnails: $($_.Exception.Message)"
        throw
    }
}

function New-FVVideoThumbnail {
    <#
    .SYNOPSIS
    Erstellt Thumbnail für Video
    
    .DESCRIPTION
    Extrahiert Frame mit FFmpeg.
    Standard: Frame bei 1 Sekunde (überspringt schwarze Intros).
    
    .PARAMETER VideoPath
    Pfad zum Video
    
    .PARAMETER OutputPath
    Pfad für Thumbnail-Output
    
    .PARAMETER Size
    Optional: Max-Größe (Default: aus Config)
    
    .PARAMETER TimeOffset
    Optional: Zeitpunkt für Frame-Extraktion in Sekunden (Default: 1)
    
    .EXAMPLE
    New-FVVideoThumbnail -VideoPath "C:\video.mp4" -OutputPath "C:\thumb.jpg"
    
    .EXAMPLE
    # Frame bei 5 Sekunden
    New-FVVideoThumbnail -VideoPath "C:\video.mp4" -OutputPath "C:\thumb.jpg" -TimeOffset 5
    
    .NOTES
    Benötigt FFmpeg
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [ValidateRange(16, 2048)]
        [int]$Size,
        
        [Parameter()]
        [ValidateRange(0, 3600)]
        [int]$TimeOffset = 1
    )
    
    try {
        # Config laden wenn Size nicht angegeben
        if (-not $Size) {
            $config = Read-FVConfig -ErrorAction Stop
            $Size = $config.Thumbnails.Size
        }
        
        Write-Verbose "Erstelle Video-Thumbnail: $VideoPath → $OutputPath (${Size}px, @${TimeOffset}s)"
        
        # Output-Verzeichnis erstellen
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # FFmpeg-Pfad
        $ffmpeg = Get-FFmpegPath
        
        # FFmpeg-Argumente
        # -ss vor -i für schnelleres Seeking
        # -vframes 1 für einen Frame
        # -vf scale für Größe (Aspect-Ratio erhalten)
        $arguments = @(
            '-ss', $TimeOffset
            '-i', $VideoPath
            '-vframes', '1'
            '-vf', "scale='min($Size,iw)':min'($Size,ih)':force_original_aspect_ratio=decrease"
            '-q:v', '2'
            '-y'
            $OutputPath
        )
        
        Write-Verbose "FFmpeg: $ffmpeg $($arguments -join ' ')"
        
        # FFmpeg ausführen
        $process = & $ffmpeg @arguments 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg fehlgeschlagen (Exit: $LASTEXITCODE): $process"
        }
        
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            throw "Thumbnail wurde nicht erstellt"
        }
        
        Write-Verbose "Video-Thumbnail erstellt: $OutputPath"
        
    } catch {
        Write-Error "Fehler beim Erstellen des Video-Thumbnails: $($_.Exception.Message)"
        throw
    }
}

function New-FVThumbnail {
    <#
    .SYNOPSIS
    Erstellt Thumbnail (Auto-Detect: Bild/Video)
    
    .DESCRIPTION
    Erkennt automatisch ob Bild oder Video und ruft passende Funktion auf.
    Nutzt Cache (gibt existierenden Thumbnail-Pfad zurück wenn vorhanden).
    
    .PARAMETER MediaPath
    Pfad zur Medien-Datei
    
    .PARAMETER Force
    Optional: Thumbnail neu generieren (Cache ignorieren)
    
    .EXAMPLE
    $thumbPath = New-FVThumbnail -MediaPath "C:\photo.jpg"
    
    .EXAMPLE
    # Cache ignorieren
    $thumbPath = New-FVThumbnail -MediaPath "C:\photo.jpg" -Force
    
    .OUTPUTS
    String - Pfad zum Thumbnail
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$MediaPath,
        
        [Parameter()]
        [switch]$Force
    )
    
    try {
        Write-Verbose "Thumbnail-Request: $MediaPath"
        
        # Cache prüfen
        $thumbPath = Get-FVThumbnailPath -MediaPath $MediaPath
        
        if (-not $Force -and (Test-Path -LiteralPath $thumbPath)) {
            Write-Verbose "Thumbnail existiert bereits (Cache): $thumbPath"
            return $thumbPath
        }
        
        # Type erkennen
        $ext = [System.IO.Path]::GetExtension($MediaPath).ToLower()
        
        $config = Read-FVConfig -ErrorAction Stop
        $imageExts = $config.MediaExtensions.Images
        $videoExts = $config.MediaExtensions.Videos
        
        if ($ext -in $imageExts) {
            # Bild
            Write-Verbose "Type: Bild"
            New-FVImageThumbnail -ImagePath $MediaPath -OutputPath $thumbPath
            
        } elseif ($ext -in $videoExts) {
            # Video
            Write-Verbose "Type: Video"
            New-FVVideoThumbnail -VideoPath $MediaPath -OutputPath $thumbPath
            
        } else {
            throw "Unbekannter Medien-Typ: $ext"
        }
        
        return $thumbPath
        
    } catch {
        Write-Error "Fehler beim Erstellen des Thumbnails: $($_.Exception.Message)"
        throw
    }
}