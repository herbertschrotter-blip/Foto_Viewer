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
    
    Für Videos mit mehreren Frames:
    - C:\Videos\.thumbs\movie_1.jpg
    - C:\Videos\.thumbs\movie_2.jpg
    - C:\Videos\.thumbs\movie_3.jpg
    
    .PARAMETER MediaPath
    Pfad zur Medien-Datei
    
    .PARAMETER FrameIndex
    Optional: Frame-Index für Video-Thumbs (1, 2, 3, ...)
    Für Bilder: ignoriert
    
    .EXAMPLE
    # Bild
    $thumbPath = Get-FVThumbnailPath -MediaPath "C:\Photos\vacation.jpg"
    # → C:\Photos\.thumbs\vacation.jpg
    
    .EXAMPLE
    # Video (einzelner Frame)
    $thumbPath = Get-FVThumbnailPath -MediaPath "C:\Videos\movie.mp4" -FrameIndex 1
    # → C:\Videos\.thumbs\movie_1.jpg
    
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
        [ValidateRange(1, 100)]
        [int]$FrameIndex
    )
    
    try {
        # Datei-Info
        $fileInfo = Get-Item -LiteralPath $MediaPath
        
        # Parent-Ordner
        $parentDir = $fileInfo.DirectoryName
        
        # .thumbs Ordner im gleichen Verzeichnis
        $thumbDir = Join-Path $parentDir ".thumbs"
        
        # Dateiname
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileInfo.Name)
        
        # Thumbnail-Pfad
        if ($FrameIndex) {
            # Video mit Frame-Index: movie_1.jpg, movie_2.jpg
            $thumbPath = Join-Path $thumbDir "${baseName}_${FrameIndex}.jpg"
        } else {
            # Bild oder Video ohne Index: vacation.jpg
            $thumbPath = Join-Path $thumbDir "$baseName.jpg"
        }
        
        Write-Verbose "Thumbnail-Pfad: $MediaPath → $thumbPath"
        
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
    Erstellt Thumbnail(s) für Video
    
    .DESCRIPTION
    Extrahiert Frame(s) mit FFmpeg.
    Unterstützt mehrere Frames basierend auf Config.
    
    .PARAMETER VideoPath
    Pfad zum Video
    
    .PARAMETER OutputPath
    Pfad für Thumbnail-Output (ohne _N.jpg Suffix!)
    
    .PARAMETER Size
    Optional: Max-Größe (Default: aus Config)
    
    .PARAMETER TimeOffset
    Optional: Zeitpunkt für Frame-Extraktion in Sekunden
    Ignoriert wenn MultiFrame aktiv
    
    .PARAMETER FrameIndex
    Optional: Frame-Index für Multi-Frame (1, 2, 3, ...)
    
    .EXAMPLE
    # Einzelner Frame
    New-FVVideoThumbnail -VideoPath "C:\video.mp4" -OutputPath "C:\.thumbs\video.jpg"
    
    .EXAMPLE
    # Multi-Frame (intern verwendet)
    New-FVVideoThumbnail -VideoPath "C:\video.mp4" -OutputPath "C:\.thumbs\video_1.jpg" -TimeOffset 10 -FrameIndex 1
    
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
        [ValidateRange(0, 36000)]
        [double]$TimeOffset = 1,
        
        [Parameter()]
        [int]$FrameIndex
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
            
            # Video-Dauer ermitteln
            $duration = Get-FVVideoDuration -VideoPath $MediaPath -ErrorAction Stop
            
            # Config: Anzahl Frames
            $frameCount = if ($config.Thumbnails.VideoFrames) {
                $config.Thumbnails.VideoFrames
            } else {
                1  # Fallback: 1 Frame
            }
            
            # Config: Frame-Range
            $rangeStart = if ($config.Thumbnails.VideoFrameRangeStart) {
                $config.Thumbnails.VideoFrameRangeStart
            } else {
                0.2  # Fallback: 20%
            }
            
            $rangeEnd = if ($config.Thumbnails.VideoFrameRangeEnd) {
                $config.Thumbnails.VideoFrameRangeEnd
            } else {
                0.9  # Fallback: 90%
            }
            
            Write-Verbose "Video-Duration: $duration Sekunden, Frames: $frameCount, Range: ${rangeStart}-${rangeEnd}"
            
            # Frames generieren
            for ($i = 1; $i -le $frameCount; $i++) {
                # Zeitpunkt berechnen (verteilt über Range)
                if ($frameCount -eq 1) {
                    # Einzelner Frame: Mitte der Range
                    $position = ($rangeStart + $rangeEnd) / 2
                } else {
                    # Mehrere Frames: gleichmäßig verteilt
                    $position = $rangeStart + (($rangeEnd - $rangeStart) / ($frameCount - 1)) * ($i - 1)
                }
                
                $timeOffset = [Math]::Round($duration * $position, 2)
                
                # Thumb-Pfad mit Frame-Index
                $frameThumbPath = Get-FVThumbnailPath -MediaPath $MediaPath -FrameIndex $i
                
                Write-Verbose "Frame $i/$frameCount @ ${timeOffset}s (${position}%) → $frameThumbPath"
                
                # Thumbnail erstellen
                New-FVVideoThumbnail -VideoPath $MediaPath `
                                     -OutputPath $frameThumbPath `
                                     -TimeOffset $timeOffset `
                                     -FrameIndex $i
            }
            
            # Hauptpfad zurückgeben (erster Frame)
            return Get-FVThumbnailPath -MediaPath $MediaPath -FrameIndex 1
            
        } else {
            throw "Unbekannter Medien-Typ: $ext"
        }
        
        return $thumbPath
        
    } catch {
        Write-Error "Fehler beim Erstellen des Thumbnails: $($_.Exception.Message)"
        throw
    }
}