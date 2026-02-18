<#
.SYNOPSIS
Video-Metadata Extractor für Foto_Viewer

.DESCRIPTION
Extrahiert Video-Metadaten mit FFprobe (JSON-Output).
Moderne Implementierung statt Regex-Parsing.

Funktionen:
- Get-FVVideoMetadata: Video-Metadaten extrahieren
- Test-FVVideoCompatible: Prüft ob Video browser-kompatibel ist
- Get-FVVideoCodec: Holt Video-Codec
- Get-FVVideoDuration: Holt Video-Dauer
- Get-FVVideoResolution: Holt Auflösung

Features:
- FFprobe JSON-Parsing (strukturiert!)
- Video + Audio Streams
- Codec-Erkennung
- Browser-Kompatibilität-Check
- Fehlerhafte Videos erkennen

.EXAMPLE
# Metadaten abrufen
$meta = Get-FVVideoMetadata -VideoPath "C:\video.mp4"
Write-Host "Codec: $($meta.VideoCodec)"
Write-Host "Duration: $($meta.DurationSeconds)s"
Write-Host "Resolution: $($meta.Width)x$($meta.Height)"

.EXAMPLE
# Kompatibilität prüfen
if (Test-FVVideoCompatible -VideoPath "C:\video.avi") {
    Write-Host "Video ist browser-kompatibel"
} else {
    Write-Host "Video muss konvertiert werden"
}

.NOTES
Autor: Herbert Schrotter
Version: 1.0.0
Erstellt: 2025-02-18
Projekt: Foto_Viewer

Benötigt:
- FFprobe (ffprobe.exe im Path oder Tools/ffmpeg/)

.LINK
https://github.com/herbertschrotter-blip/Foto_Viewer
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

function Get-FFprobePath {
    <#
    .SYNOPSIS
    Sucht FFprobe.exe
    
    .DESCRIPTION
    Sucht in:
    1. Tools/ffmpeg/ffprobe.exe (Projekt)
    2. $env:PATH (System)
    
    .OUTPUTS
    String - Pfad zu ffprobe.exe
    
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
        $toolsPath = Join-Path $projectRoot "Tools\ffmpeg\ffprobe.exe"
        
        if (Test-Path -LiteralPath $toolsPath) {
            Write-Verbose "FFprobe gefunden: $toolsPath"
            return $toolsPath
        }
        
        # 2. System PATH
        $systemFFprobe = Get-Command ffprobe.exe -ErrorAction SilentlyContinue
        if ($systemFFprobe) {
            Write-Verbose "FFprobe gefunden in PATH: $($systemFFprobe.Source)"
            return $systemFFprobe.Source
        }
        
        throw "FFprobe nicht gefunden. Bitte installiere FFmpeg in Tools/ffmpeg/ oder System PATH."
        
    } catch {
        Write-Error "Fehler beim Suchen von FFprobe: $($_.Exception.Message)"
        throw
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Get-FVVideoMetadata {
    <#
    .SYNOPSIS
    Extrahiert Video-Metadaten
    
    .DESCRIPTION
    Verwendet FFprobe mit JSON-Output für strukturierte Daten.
    
    Gibt Metadata-Objekt zurück:
    - VideoCodec: h264, hevc, mpeg4, etc.
    - AudioCodec: aac, mp3, etc.
    - Width: Pixel
    - Height: Pixel
    - DurationSeconds: Sekunden
    - Bitrate: Gesamt-Bitrate
    - FrameRate: FPS
    - Format: Container (mp4, avi, etc.)
    - IsCompatible: Browser-kompatibel?
    
    .PARAMETER VideoPath
    Pfad zur Video-Datei
    
    .EXAMPLE
    $meta = Get-FVVideoMetadata -VideoPath "C:\video.mp4"
    
    .EXAMPLE
    # Mit Verbose
    $meta = Get-FVVideoMetadata -VideoPath "C:\video.avi" -Verbose
    
    .OUTPUTS
    PSCustomObject mit Video-Metadaten
    
    .NOTES
    Wirft Exception wenn:
    - Datei nicht existiert
    - FFprobe nicht gefunden
    - Video beschädigt/ungültig
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$VideoPath
    )
    
    try {
        Write-Verbose "Extrahiere Metadaten: $VideoPath"
        
        # FFprobe-Pfad
        $ffprobe = Get-FFprobePath
        
        # Temporäre Output-Datei
        $outputFile = "$env:TEMP\ffprobe_output_$(Get-Random).json"
        
        # FFprobe-Argumente
        $arguments = @(
            '-v', 'quiet'
            '-print_format', 'json'
            '-show_format'
            '-show_streams'
            $VideoPath
        )
        
        Write-Verbose "FFprobe: $ffprobe $($arguments -join ' ')"
        
        # FFprobe ausführen mit & Operator (funktioniert besser als Start-Process)
        $jsonOutput = & $ffprobe @arguments 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "FFprobe fehlgeschlagen (Exit: $LASTEXITCODE)"
        }
        
        # JSON parsen
        $jsonString = $jsonOutput | Out-String
        
        if ([string]::IsNullOrWhiteSpace($jsonString)) {
            throw "FFprobe gab keine Daten zurück"
        }
        
        $data = $jsonString | ConvertFrom-Json
        
        # Video-Stream finden
        $videoStream = $data.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
        
        if (-not $videoStream) {
            throw "Kein Video-Stream gefunden"
        }
        
        # Audio-Stream finden
        $audioStream = $data.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1
        
        # Metadaten extrahieren
        $videoCodec = $videoStream.codec_name
        $audioCodec = if ($audioStream) { $audioStream.codec_name } else { $null }
        
        $width = [int]$videoStream.width
        $height = [int]$videoStream.height
        
        $duration = if ($data.format.duration) {
            [double]$data.format.duration
        } elseif ($videoStream.duration) {
            [double]$videoStream.duration
        } else {
            0
        }
        
        $bitrate = if ($data.format.bit_rate) {
            [int]$data.format.bit_rate
        } else {
            0
        }
        
        # Frame-Rate berechnen
        $frameRate = 0.0
        if ($videoStream.r_frame_rate -and $videoStream.r_frame_rate -ne '0/0') {
            $parts = $videoStream.r_frame_rate -split '/'
            if ($parts.Count -eq 2 -and [int]$parts[1] -ne 0) {
                $frameRate = [double]$parts[0] / [double]$parts[1]
            }
        }
        
        # Format/Container
        $format = $data.format.format_name -split ',' | Select-Object -First 1
        
        # Browser-Kompatibilität prüfen
        $compatibleCodecs = @('h264', 'hevc', 'vp8', 'vp9', 'av1')
        $compatibleContainers = @('mp4', 'webm', 'mov')
        
        $isCompatible = ($videoCodec -in $compatibleCodecs) -and ($format -in $compatibleContainers)
        
        # Metadata-Objekt erstellen
        $metadata = [PSCustomObject]@{
            VideoPath = $VideoPath
            VideoCodec = $videoCodec
            AudioCodec = $audioCodec
            Width = $width
            Height = $height
            DurationSeconds = [Math]::Round($duration, 2)
            Bitrate = $bitrate
            FrameRate = [Math]::Round($frameRate, 2)
            Format = $format
            IsCompatible = $isCompatible
            HasAudio = $null -ne $audioStream
        }
        
        Write-Verbose "Metadaten extrahiert: $videoCodec, ${width}x${height}, ${duration}s"
        
        return $metadata
        
    } catch {
        Write-Error "Fehler beim Extrahieren der Video-Metadaten: $($_.Exception.Message)"
        throw
    }
}

function Test-FVVideoCompatible {
    <#
    .SYNOPSIS
    Prüft ob Video browser-kompatibel ist
    
    .DESCRIPTION
    Prüft Codec und Container gegen Browser-Support.
    
    Browser-kompatibel:
    - Codecs: h264, hevc, vp8, vp9, av1
    - Container: mp4, webm, mov
    
    .PARAMETER VideoPath
    Pfad zur Video-Datei
    
    .EXAMPLE
    if (Test-FVVideoCompatible -VideoPath "C:\video.mp4") {
        Write-Host "Video kann direkt abgespielt werden"
    } else {
        Write-Host "Video muss konvertiert werden"
    }
    
    .OUTPUTS
    Boolean
    #>
    
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$VideoPath
    )
    
    try {
        $metadata = Get-FVVideoMetadata -VideoPath $VideoPath -ErrorAction Stop
        return $metadata.IsCompatible
        
    } catch {
        Write-Verbose "Fehler beim Prüfen der Kompatibilität: $($_.Exception.Message)"
        return $false
    }
}

function Get-FVVideoCodec {
    <#
    .SYNOPSIS
    Holt Video-Codec
    
    .DESCRIPTION
    Extrahiert nur Video-Codec (schneller als komplette Metadaten).
    
    .PARAMETER VideoPath
    Pfad zur Video-Datei
    
    .EXAMPLE
    $codec = Get-FVVideoCodec -VideoPath "C:\video.mp4"
    Write-Host "Codec: $codec"  # → h264
    
    .OUTPUTS
    String - Codec-Name
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$VideoPath
    )
    
    try {
        $metadata = Get-FVVideoMetadata -VideoPath $VideoPath -ErrorAction Stop
        return $metadata.VideoCodec
        
    } catch {
        Write-Error "Fehler beim Abrufen des Video-Codecs: $($_.Exception.Message)"
        throw
    }
}

function Get-FVVideoDuration {
    <#
    .SYNOPSIS
    Holt Video-Dauer
    
    .DESCRIPTION
    Gibt Dauer in Sekunden zurück.
    
    .PARAMETER VideoPath
    Pfad zur Video-Datei
    
    .EXAMPLE
    $duration = Get-FVVideoDuration -VideoPath "C:\video.mp4"
    Write-Host "Dauer: $duration Sekunden"
    
    .OUTPUTS
    Double - Dauer in Sekunden
    #>
    
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$VideoPath
    )
    
    try {
        $metadata = Get-FVVideoMetadata -VideoPath $VideoPath -ErrorAction Stop
        return $metadata.DurationSeconds
        
    } catch {
        Write-Error "Fehler beim Abrufen der Video-Dauer: $($_.Exception.Message)"
        throw
    }
}

function Get-FVVideoResolution {
    <#
    .SYNOPSIS
    Holt Video-Auflösung
    
    .DESCRIPTION
    Gibt Width und Height zurück.
    
    .PARAMETER VideoPath
    Pfad zur Video-Datei
    
    .EXAMPLE
    $res = Get-FVVideoResolution -VideoPath "C:\video.mp4"
    Write-Host "Auflösung: $($res.Width)x$($res.Height)"
    
    .OUTPUTS
    PSCustomObject mit Width und Height
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$VideoPath
    )
    
    try {
        $metadata = Get-FVVideoMetadata -VideoPath $VideoPath -ErrorAction Stop
        
        return [PSCustomObject]@{
            Width = $metadata.Width
            Height = $metadata.Height
        }
        
    } catch {
        Write-Error "Fehler beim Abrufen der Video-Auflösung: $($_.Exception.Message)"
        throw
    }
}