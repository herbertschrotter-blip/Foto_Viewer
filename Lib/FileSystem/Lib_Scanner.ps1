<#
.SYNOPSIS
File-System Scanner für Foto_Viewer

.DESCRIPTION
Scannt Verzeichnisse nach Medien-Dateien (Bilder + Videos).
Optimiert für Performance mit Caching.

Funktionen:
- Invoke-FVScan: Rekursiver Ordner-Scan
- Get-FVMediaFiles: Medien-Dateien abrufen
- Get-FVFolderStructure: Ordner-Hierarchie erstellen
- Test-FVMediaFile: Prüft ob Datei Medien-Datei ist

Features:
- Schneller rekursiver Scan
- Extension-Filter aus Config
- Type-Filter (Images, Videos, All)
- Relative Pfade für Caching
- Sortierung nach Name/Date/Size

.EXAMPLE
# Ordner scannen
$media = Invoke-FVScan -Path "C:\Photos" -Recursive
Write-Host "Gefunden: $($media.Count) Dateien"

.EXAMPLE
# Nur Bilder
$images = Get-FVMediaFiles -Path "C:\Photos" -Type Images

.EXAMPLE
# Ordner-Struktur
$folders = Get-FVFolderStructure -Path "C:\Photos"

.NOTES
Autor: Herbert Schrotter
Version: 1.0.1
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

function Invoke-FVScan {
    <#
    .SYNOPSIS
    Scannt Verzeichnis nach Medien-Dateien
    
    .DESCRIPTION
    Durchsucht angegebenen Pfad nach Bildern und Videos.
    Filtert nach konfigurierten Extensions.
    Ignoriert .thumbs Ordner.
    
    .PARAMETER Path
    Zu scannender Pfad
    
    .PARAMETER Recursive
    Rekursiv scannen (Default: $true)
    
    .PARAMETER Type
    Filter nach Typ: All, Images, Videos (Default: All)
    
    .PARAMETER SortBy
    Sortierung: Name, Date, Size (Default: Name)
    
    .EXAMPLE
    $media = Invoke-FVScan -Path "C:\Photos"
    
    .EXAMPLE
    $images = Invoke-FVScan -Path "C:\Photos" -Type Images -Recursive $false
    
    .OUTPUTS
    Array von PSCustomObjects mit Media-Dateien
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$Path,
        
        [Parameter()]
        [bool]$Recursive = $true,
        
        [Parameter()]
        [ValidateSet('All', 'Images', 'Videos')]
        [string]$Type = 'All',
        
        [Parameter()]
        [ValidateSet('Name', 'Date', 'Size')]
        [string]$SortBy = 'Name'
    )
    
    try {
        Write-Verbose "Scanne Pfad: $Path (Recursive: $Recursive, Type: $Type)"
        
        # Config laden
        $config = Read-FVConfig -ErrorAction Stop
        
        # Extensions (aus MediaExtensions!)
        $imageExts = $config.MediaExtensions.Images
        $videoExts = $config.MediaExtensions.Videos
        
        # Filter Extensions
        $allExtensions = switch ($Type) {
            'Images' { $imageExts }
            'Videos' { $videoExts }
            default { $imageExts + $videoExts }
        }
        
        Write-Verbose "Extensions: $($allExtensions -join ', ')"
        
        # Dateien scannen (ARRAY ERZWINGEN!)
        $items = @(Get-ChildItem -LiteralPath $Path -Recurse:$Recursive -File -ErrorAction Stop |
            Where-Object { 
                # .thumbs Ordner ignorieren!
                $_.DirectoryName -notlike '*\.thumbs*' -and
                $_.FullName -notlike '*\.thumbs\*' -and
                # Extension-Filter
                $_.Extension.ToLower() -in $allExtensions
            })
        
        Write-Verbose "Dateien gefunden: $($items.Count)"
        
        # Medien-Objekte erstellen (ARRAY ERZWINGEN!)
        $media = @($items | ForEach-Object {
            $file = $_
            
            # Type bestimmen
            $fileType = if ($file.Extension.ToLower() -in $imageExts) {
                'Image'
            } elseif ($file.Extension.ToLower() -in $videoExts) {
                'Video'
            } else {
                'Unknown'
            }
            
            # Relativer Pfad
            $relativePath = $file.FullName.Replace($Path, '').TrimStart('\', '/')
            
            [PSCustomObject]@{
                Name = $file.Name
                Path = $file.FullName
                RelativePath = $relativePath
                Extension = $file.Extension
                Type = $fileType
                Size = $file.Length
                LastModified = $file.LastWriteTime
                Directory = $file.DirectoryName
            }
        })
        
        # Sortierung
        $media = @(switch ($SortBy) {
            'Date' { $media | Sort-Object LastModified -Descending }
            'Size' { $media | Sort-Object Size -Descending }
            default { $media | Sort-Object Name }
        })
        
        Write-Verbose "Medien verarbeitet: $($media.Count)"
        
        return $media
        
    } catch {
        Write-Error "Fehler beim Scannen: $($_.Exception.Message)"
        throw
    }
}

function Get-FVMediaFiles {
    <#
    .SYNOPSIS
    Holt Medien-Dateien aus Verzeichnis
    
    .DESCRIPTION
    Wrapper um Invoke-FVScan mit vereinfachter API.
    
    .PARAMETER Path
    Verzeichnis
    
    .PARAMETER Type
    Optional: Filter (All, Images, Videos)
    
    .PARAMETER Recursive
    Optional: Rekursiv (Default: $true)
    
    .EXAMPLE
    $images = Get-FVMediaFiles -Path "C:\Photos" -Type Images
    
    .EXAMPLE
    $all = Get-FVMediaFiles -Path "C:\Photos"
    
    .OUTPUTS
    Array von Medien-Objekten
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$Path,
        
        [Parameter()]
        [ValidateSet('All', 'Images', 'Videos')]
        [string]$Type = 'All',
        
        [Parameter()]
        [bool]$Recursive = $true
    )
    
    try {
        return Invoke-FVScan -Path $Path -Type $Type -Recursive $Recursive
        
    } catch {
        Write-Error "Fehler beim Abrufen der Medien-Dateien: $($_.Exception.Message)"
        throw
    }
}

function Get-FVFolderStructure {
    <#
    .SYNOPSIS
    Erstellt Ordner-Hierarchie
    
    .DESCRIPTION
    Scannt Verzeichnis und erstellt Ordner-Baum mit Medien-Counts.
    
    Gibt Ordner-Objekte zurück:
    - Path: Absoluter Pfad
    - RelativePath: Relativ zu RootPath
    - Name: Ordner-Name
    - ImageCount: Anzahl Bilder
    - VideoCount: Anzahl Videos
    - TotalCount: Gesamt
    - SubFolders: Array von Unter-Ordnern
    
    .PARAMETER Path
    Wurzel-Verzeichnis
    
    .PARAMETER Recursive
    Optional: Rekursiv (Default: $true)
    
    .EXAMPLE
    $structure = Get-FVFolderStructure -Path "C:\Photos"
    
    .EXAMPLE
    # Nur direkte Unter-Ordner
    $folders = Get-FVFolderStructure -Path "C:\Photos" -Recursive:$false
    
    .OUTPUTS
    Array von Ordner-Objekten
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$Path,
        
        [Parameter()]
        [bool]$Recursive = $true
    )
    
    try {
        Write-Verbose "Erstelle Ordner-Struktur: $Path"
        
        # Ordner scannen
        $scanParams = @{
            LiteralPath = $Path
            Directory = $true
            ErrorAction = 'SilentlyContinue'
        }
        
        if ($Recursive) {
            $scanParams.Recurse = $true
        }
        
        $folders = @(Get-ChildItem @scanParams)
        
        Write-Verbose "Ordner gefunden: $($folders.Count)"
        
        # Config für Extensions
        $config = Read-FVConfig -ErrorAction Stop
        $imageExts = $config.MediaExtensions.Images
        $videoExts = $config.MediaExtensions.Videos
        
        # Für jeden Ordner: Medien zählen
        $folderObjects = @()
        
        foreach ($folder in $folders) {
            # Dateien in diesem Ordner
            $files = @(Get-ChildItem -LiteralPath $folder.FullName -File -ErrorAction SilentlyContinue)
            
            # Bilder zählen
            $imageCount = @($files | Where-Object { $_.Extension.ToLower() -in $imageExts }).Count
            
            # Videos zählen
            $videoCount = @($files | Where-Object { $_.Extension.ToLower() -in $videoExts }).Count
            
            # Relativen Pfad
            $relativePath = $folder.FullName.Replace($Path, '').TrimStart('\', '/')
            
            $folderObj = [PSCustomObject]@{
                Path = $folder.FullName
                RelativePath = $relativePath
                Name = $folder.Name
                ImageCount = $imageCount
                VideoCount = $videoCount
                TotalCount = $imageCount + $videoCount
            }
            
            $folderObjects += $folderObj
        }
        
        Write-Verbose "Ordner-Struktur erstellt: $($folderObjects.Count) Ordner"
        
        return $folderObjects
        
    } catch {
        Write-Error "Fehler beim Erstellen der Ordner-Struktur: $($_.Exception.Message)"
        throw
    }
}

function Test-FVMediaFile {
    <#
    .SYNOPSIS
    Prüft ob Datei Medien-Datei ist
    
    .DESCRIPTION
    Prüft Extension gegen Config-Extensions.
    
    .PARAMETER Path
    Dateipfad
    
    .PARAMETER Type
    Optional: Type-Check (All, Image, Video)
    Default: All
    
    .EXAMPLE
    if (Test-FVMediaFile -Path "C:\photo.jpg") {
        Write-Host "Ist Medien-Datei"
    }
    
    .EXAMPLE
    if (Test-FVMediaFile -Path "C:\video.mp4" -Type Video) {
        Write-Host "Ist Video"
    }
    
    .OUTPUTS
    Boolean
    #>
    
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter()]
        [ValidateSet('All', 'Image', 'Video')]
        [string]$Type = 'All'
    )
    
    try {
        # Extension holen
        $ext = [System.IO.Path]::GetExtension($Path).ToLower()
        
        if ([string]::IsNullOrEmpty($ext)) {
            return $false
        }
        
        # Config laden
        $config = Read-FVConfig -ErrorAction Stop
        $imageExts = $config.MediaExtensions.Images
        $videoExts = $config.MediaExtensions.Videos
        
        # Type-Check
        $result = switch ($Type) {
            'Image' { $ext -in $imageExts }
            'Video' { $ext -in $videoExts }
            'All'   { ($ext -in $imageExts) -or ($ext -in $videoExts) }
        }
        
        Write-Verbose "Test-FVMediaFile: $Path → $result (Type: $Type)"
        return $result
        
    } catch {
        Write-Verbose "Fehler beim Prüfen der Medien-Datei: $($_.Exception.Message)"
        return $false
    }
}

function Get-FVMediaStats {
    <#
    .SYNOPSIS
    Erstellt Statistik über Medien-Dateien
    
    .DESCRIPTION
    Zählt Medien-Dateien und berechnet Gesamt-Größe.
    
    .PARAMETER Path
    Verzeichnis
    
    .PARAMETER Recursive
    Optional: Rekursiv (Default: $true)
    
    .EXAMPLE
    $stats = Get-FVMediaStats -Path "C:\Photos"
    Write-Host "Images: $($stats.ImageCount)"
    Write-Host "Videos: $($stats.VideoCount)"
    Write-Host "Total Size: $($stats.TotalSizeGB) GB"
    
    .OUTPUTS
    PSCustomObject mit Statistiken
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$Path,
        
        [Parameter()]
        [bool]$Recursive = $true
    )
    
    try {
        Write-Verbose "Erstelle Statistik: $Path"
        
        # Medien scannen
        $media = @(Invoke-FVScan -Path $Path -Recursive $Recursive -Type All)
        
        # Nach Type gruppieren
        $images = @($media | Where-Object Type -eq 'Image')
        $videos = @($media | Where-Object Type -eq 'Video')
        
        # Größen berechnen
        $totalSize = ($media | Measure-Object -Property Size -Sum).Sum
        $imageSize = ($images | Measure-Object -Property Size -Sum).Sum
        $videoSize = ($videos | Measure-Object -Property Size -Sum).Sum
        
        $stats = [PSCustomObject]@{
            Path = $Path
            ImageCount = $images.Count
            VideoCount = $videos.Count
            TotalCount = $media.Count
            ImageSizeBytes = $imageSize
            VideoSizeBytes = $videoSize
            TotalSizeBytes = $totalSize
            ImageSizeMB = [Math]::Round($imageSize / 1MB, 2)
            VideoSizeMB = [Math]::Round($videoSize / 1MB, 2)
            TotalSizeMB = [Math]::Round($totalSize / 1MB, 2)
            ImageSizeGB = [Math]::Round($imageSize / 1GB, 2)
            VideoSizeGB = [Math]::Round($videoSize / 1GB, 2)
            TotalSizeGB = [Math]::Round($totalSize / 1GB, 2)
        }
        
        Write-Verbose "Statistik erstellt: $($stats.TotalCount) Dateien, $($stats.TotalSizeGB) GB"
        
        return $stats
        
    } catch {
        Write-Error "Fehler beim Erstellen der Statistik: $($_.Exception.Message)"
        throw
    }
}