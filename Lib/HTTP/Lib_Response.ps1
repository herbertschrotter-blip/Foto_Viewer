<#
.SYNOPSIS
HTTP-Response Handling für Foto_Viewer

.DESCRIPTION
Vereinfacht das Senden von HTTP-Responses:
- HTML-Responses
- JSON-Responses
- File-Responses (Bilder, Videos, etc.)
- Stream-Responses (mit Range-Support für Video-Streaming)
- Error-Responses (404, 500, etc.)

Funktionen:
- Send-FVHtmlResponse: HTML zurückschicken
- Send-FVJsonResponse: JSON zurückschicken
- Send-FVFileResponse: Datei zurückschicken
- Send-FVStreamResponse: File-Stream mit Range-Support
- Send-FVErrorResponse: Error-Response (404, 500, etc.)

.EXAMPLE
# HTML senden
Send-FVHtmlResponse -Response $response -Html "<h1>Hello</h1>"

.EXAMPLE
# JSON senden
$data = @{ status="ok"; count=42 }
Send-FVJsonResponse -Response $response -Data $data

.EXAMPLE
# Datei senden
Send-FVFileResponse -Response $response -FilePath "C:\photo.jpg"

.EXAMPLE
# Stream mit Range-Support (für Videos)
Send-FVStreamResponse -Response $response -FilePath "C:\video.mp4"

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
# INTERNAL HELPERS
# ============================================================================

function Get-ContentType {
    <#
    .SYNOPSIS
    Ermittelt Content-Type anhand Datei-Extension
    
    .DESCRIPTION
    Gibt MIME-Type für häufige Dateitypen zurück.
    
    .PARAMETER FilePath
    Dateipfad
    
    .EXAMPLE
    $contentType = Get-ContentType -FilePath "photo.jpg"
    # → "image/jpeg"
    
    .OUTPUTS
    String - MIME-Type
    
    .NOTES
    Internal Helper
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    $mimeTypes = @{
        # Images
        '.jpg' = 'image/jpeg'
        '.jpeg' = 'image/jpeg'
        '.png' = 'image/png'
        '.gif' = 'image/gif'
        '.webp' = 'image/webp'
        '.bmp' = 'image/bmp'
        '.svg' = 'image/svg+xml'
        '.ico' = 'image/x-icon'
        
        # Videos
        '.mp4' = 'video/mp4'
        '.webm' = 'video/webm'
        '.avi' = 'video/x-msvideo'
        '.mov' = 'video/quicktime'
        '.wmv' = 'video/x-ms-wmv'
        '.mkv' = 'video/x-matroska'
        '.m4v' = 'video/x-m4v'
        
        # Text/HTML/JSON
        '.html' = 'text/html; charset=utf-8'
        '.htm' = 'text/html; charset=utf-8'
        '.css' = 'text/css; charset=utf-8'
        '.js' = 'application/javascript; charset=utf-8'
        '.json' = 'application/json; charset=utf-8'
        '.txt' = 'text/plain; charset=utf-8'
        '.xml' = 'application/xml; charset=utf-8'
        
        # Fonts
        '.woff' = 'font/woff'
        '.woff2' = 'font/woff2'
        '.ttf' = 'font/ttf'
        '.otf' = 'font/otf'
    }
    
    if ($mimeTypes.ContainsKey($extension)) {
        return $mimeTypes[$extension]
    }
    
    # Fallback
    return 'application/octet-stream'
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Send-FVHtmlResponse {
    <#
    .SYNOPSIS
    Sendet HTML-Response
    
    .DESCRIPTION
    Schickt HTML-String als Response zurück zum Browser.
    Automatisch mit Content-Type: text/html; charset=utf-8
    
    .PARAMETER Response
    HttpListenerResponse-Objekt
    
    .PARAMETER Html
    HTML-String (komplettes HTML-Dokument oder Fragment)
    
    .PARAMETER StatusCode
    Optional: HTTP-Status-Code (Default: 200)
    
    .EXAMPLE
    Send-FVHtmlResponse -Response $response -Html "<h1>Hello World</h1>"
    
    .EXAMPLE
    $html = @"
<!DOCTYPE html>
<html>
<head><title>My Page</title></head>
<body><h1>Content</h1></body>
</html>
"@
    Send-FVHtmlResponse -Response $response -Html $html
    
    .EXAMPLE
    # Mit Custom Status-Code
    Send-FVHtmlResponse -Response $response -Html "<h1>Created</h1>" -StatusCode 201
    
    .NOTES
    Response wird automatisch geschlossen
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Html,
        
        [Parameter()]
        [ValidateRange(100, 599)]
        [int]$StatusCode = 200
    )
    
    try {
        Write-Verbose "Sende HTML-Response ($($Html.Length) Zeichen, Status: $StatusCode)"
        
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($Html)
        
        $Response.StatusCode = $StatusCode
        $Response.ContentType = 'text/html; charset=utf-8'
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.Close()
        
        Write-Verbose "HTML-Response gesendet: $($buffer.Length) bytes"
        
    } catch {
        Write-Error "Fehler beim Senden der HTML-Response: $($_.Exception.Message)"
        throw
    }
}

function Send-FVJsonResponse {
    <#
    .SYNOPSIS
    Sendet JSON-Response
    
    .DESCRIPTION
    Konvertiert Objekt zu JSON und schickt als Response zurück.
    Automatisch mit Content-Type: application/json; charset=utf-8
    
    .PARAMETER Response
    HttpListenerResponse-Objekt
    
    .PARAMETER Data
    Objekt zum Konvertieren (Hashtable, PSCustomObject, Array, etc.)
    
    .PARAMETER StatusCode
    Optional: HTTP-Status-Code (Default: 200)
    
    .PARAMETER Depth
    Optional: JSON-Depth für ConvertTo-Json (Default: 10)
    
    .EXAMPLE
    $data = @{ status="ok"; count=42 }
    Send-FVJsonResponse -Response $response -Data $data
    # → {"status":"ok","count":42}
    
    .EXAMPLE
    $array = @(
        @{ id=1; name="Item 1" },
        @{ id=2; name="Item 2" }
    )
    Send-FVJsonResponse -Response $response -Data $array
    
    .EXAMPLE
    # Mit Custom Status-Code
    $error = @{ error="Not Found"; code=404 }
    Send-FVJsonResponse -Response $response -Data $error -StatusCode 404
    
    .NOTES
    Response wird automatisch geschlossen
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Data,
        
        [Parameter()]
        [ValidateRange(100, 599)]
        [int]$StatusCode = 200,
        
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Depth = 10
    )
    
    try {
        Write-Verbose "Sende JSON-Response (Status: $StatusCode)"
        
        # Zu JSON konvertieren
        $json = $Data | ConvertTo-Json -Depth $Depth -Compress
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        
        $Response.StatusCode = $StatusCode
        $Response.ContentType = 'application/json; charset=utf-8'
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.Close()
        
        Write-Verbose "JSON-Response gesendet: $($buffer.Length) bytes"
        
    } catch {
        Write-Error "Fehler beim Senden der JSON-Response: $($_.Exception.Message)"
        throw
    }
}

function Send-FVFileResponse {
    <#
    .SYNOPSIS
    Sendet Datei-Response
    
    .DESCRIPTION
    Schickt komplette Datei als Response zurück.
    Content-Type wird automatisch anhand Extension ermittelt.
    
    Für große Dateien oder Videos: Verwende Send-FVStreamResponse
    
    .PARAMETER Response
    HttpListenerResponse-Objekt
    
    .PARAMETER FilePath
    Absoluter Pfad zur Datei
    
    .PARAMETER StatusCode
    Optional: HTTP-Status-Code (Default: 200)
    
    .EXAMPLE
    Send-FVFileResponse -Response $response -FilePath "C:\Photos\image.jpg"
    
    .EXAMPLE
    Send-FVFileResponse -Response $response -FilePath "C:\Videos\small.mp4"
    
    .NOTES
    Lädt komplette Datei in Memory → Nicht für große Dateien!
    Für Videos >10MB: Verwende Send-FVStreamResponse
    Response wird automatisch geschlossen
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,
        
        [Parameter()]
        [ValidateRange(100, 599)]
        [int]$StatusCode = 200
    )
    
    try {
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $FilePath)) {
            throw "Datei nicht gefunden: $FilePath"
        }
        
        $fileInfo = Get-Item -LiteralPath $FilePath
        Write-Verbose "Sende Datei: $($fileInfo.Name) ($($fileInfo.Length) bytes)"
        
        # Content-Type ermitteln
        $contentType = Get-ContentType -FilePath $FilePath
        
        # Datei lesen
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        
        # Response senden
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $contentType
        $Response.ContentLength64 = $fileBytes.Length
        $Response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
        $Response.Close()
        
        Write-Verbose "Datei-Response gesendet: $($fileBytes.Length) bytes, Type: $contentType"
        
    } catch {
        Write-Error "Fehler beim Senden der Datei-Response: $($_.Exception.Message)"
        throw
    }
}

function Send-FVStreamResponse {
    <#
    .SYNOPSIS
    Sendet File-Stream mit Range-Support
    
    .DESCRIPTION
    Schickt Datei als Stream mit Range-Request-Support.
    Ermöglicht Video-Streaming mit Seek-Funktion im Browser.
    
    Unterstützt:
    - Partial Content (HTTP 206)
    - Range-Header (bytes=0-1023)
    - Accept-Ranges
    
    .PARAMETER Response
    HttpListenerResponse-Objekt
    
    .PARAMETER Request
    HttpListenerRequest-Objekt (für Range-Header)
    
    .PARAMETER FilePath
    Absoluter Pfad zur Datei
    
    .PARAMETER BufferSize
    Optional: Buffer-Größe für Streaming (Default: 64KB)
    
    .EXAMPLE
    # Einfach (ohne Range)
    Send-FVStreamResponse -Response $response -Request $request -FilePath "C:\Videos\movie.mp4"
    
    .EXAMPLE
    # Mit Custom Buffer
    Send-FVStreamResponse -Response $response -Request $request -FilePath "C:\Videos\large.mp4" -BufferSize 1MB
    
    .NOTES
    Ideal für Videos und große Dateien.
    Browser können mit Range-Requests spulen.
    Response wird automatisch geschlossen.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerRequest]$Request,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,
        
        [Parameter()]
        [ValidateRange(1KB, 10MB)]
        [int]$BufferSize = 64KB
    )
    
    try {
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $FilePath)) {
            throw "Datei nicht gefunden: $FilePath"
        }
        
        $fileInfo = Get-Item -LiteralPath $FilePath
        $fileLength = $fileInfo.Length
        
        Write-Verbose "Streaming: $($fileInfo.Name) ($fileLength bytes)"
        
        # Content-Type ermitteln
        $contentType = Get-ContentType -FilePath $FilePath
        
        # Range-Header prüfen
        $rangeHeader = $Request.Headers["Range"]
        
        if ([string]::IsNullOrEmpty($rangeHeader)) {
            # Kein Range → Komplette Datei
            Write-Verbose "Stream: Komplette Datei"
            
            $Response.StatusCode = 200
            $Response.ContentType = $contentType
            $Response.ContentLength64 = $fileLength
            $Response.AddHeader("Accept-Ranges", "bytes")
            
            $startByte = 0
            $endByte = $fileLength - 1
            
        } else {
            # Range-Request → Partial Content
            Write-Verbose "Stream: Range-Request: $rangeHeader"
            
            # Range parsen: "bytes=0-1023"
            if ($rangeHeader -match 'bytes=(\d+)-(\d*)') {
                $startByte = [long]$matches[1]
                $endByte = if ([string]::IsNullOrEmpty($matches[2])) {
                    $fileLength - 1
                } else {
                    [long]$matches[2]
                }
                
                # Range validieren
                if ($startByte -ge $fileLength) {
                    $startByte = 0
                }
                if ($endByte -ge $fileLength) {
                    $endByte = $fileLength - 1
                }
                
                $contentLength = $endByte - $startByte + 1
                
                Write-Verbose "Stream: Range: $startByte-$endByte ($contentLength bytes)"
                
                $Response.StatusCode = 206  # Partial Content
                $Response.ContentType = $contentType
                $Response.ContentLength64 = $contentLength
                $Response.AddHeader("Accept-Ranges", "bytes")
                $Response.AddHeader("Content-Range", "bytes $startByte-$endByte/$fileLength")
                
            } else {
                # Ungültiger Range → Komplette Datei
                Write-Verbose "Stream: Ungültiger Range, sende komplett"
                
                $Response.StatusCode = 200
                $Response.ContentType = $contentType
                $Response.ContentLength64 = $fileLength
                $Response.AddHeader("Accept-Ranges", "bytes")
                
                $startByte = 0
                $endByte = $fileLength - 1
            }
        }
        
        # File-Stream öffnen
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        
        try {
            # An Start-Position springen
            if ($startByte -gt 0) {
                [void]$fileStream.Seek($startByte, [System.IO.SeekOrigin]::Begin)
            }
            
            # Bytes streamen
            $buffer = New-Object byte[] $BufferSize
            $bytesToSend = $endByte - $startByte + 1
            $bytesSent = 0
            
            while ($bytesSent -lt $bytesToSend) {
                $remaining = $bytesToSend - $bytesSent
                $toRead = [Math]::Min($remaining, $BufferSize)
                
                $bytesRead = $fileStream.Read($buffer, 0, $toRead)
                
                if ($bytesRead -le 0) {
                    break
                }
                
                $Response.OutputStream.Write($buffer, 0, $bytesRead)
                $bytesSent += $bytesRead
                
                Write-Verbose "Stream: $bytesSent / $bytesToSend bytes gesendet"
            }
            
            $Response.Close()
            Write-Verbose "Stream beendet: $bytesSent bytes gesendet"
            
        } finally {
            $fileStream.Close()
        }
        
    } catch {
        Write-Error "Fehler beim Streaming: $($_.Exception.Message)"
        throw
    }
}

function Send-FVErrorResponse {
    <#
    .SYNOPSIS
    Sendet Error-Response
    
    .DESCRIPTION
    Schickt formatierte Error-Response mit Status-Code.
    Automatisch gestylte HTML-Seite.
    
    .PARAMETER Response
    HttpListenerResponse-Objekt
    
    .PARAMETER StatusCode
    HTTP-Status-Code (z.B. 404, 500)
    
    .PARAMETER Message
    Optional: Custom Error-Message
    
    .PARAMETER Details
    Optional: Zusätzliche Details (nur bei Dev-Mode zeigen!)
    
    .EXAMPLE
    Send-FVErrorResponse -Response $response -StatusCode 404
    
    .EXAMPLE
    Send-FVErrorResponse -Response $response -StatusCode 500 -Message "Database connection failed"
    
    .EXAMPLE
    Send-FVErrorResponse -Response $response -StatusCode 403 -Message "Access Denied" -Details "User not authenticated"
    
    .NOTES
    Response wird automatisch geschlossen
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory)]
        [ValidateRange(400, 599)]
        [int]$StatusCode,
        
        [Parameter()]
        [string]$Message,
        
        [Parameter()]
        [string]$Details
    )
    
    try {
        # Default Messages
        $statusMessages = @{
            400 = "Bad Request"
            401 = "Unauthorized"
            403 = "Forbidden"
            404 = "Not Found"
            405 = "Method Not Allowed"
            500 = "Internal Server Error"
            501 = "Not Implemented"
            503 = "Service Unavailable"
        }
        
        if ([string]::IsNullOrEmpty($Message)) {
            $Message = if ($statusMessages.ContainsKey($StatusCode)) {
                $statusMessages[$StatusCode]
            } else {
                "Error $StatusCode"
            }
        }
        
        Write-Verbose "Sende Error-Response: $StatusCode - $Message"
        
        # HTML generieren
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$StatusCode - $Message</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: #1a1a1a;
            color: #fff;
            padding: 50px;
            text-align: center;
        }
        h1 {
            color: #f44336;
            font-size: 72px;
            margin: 0;
        }
        h2 {
            color: #ff9800;
            margin: 10px 0;
        }
        .details {
            background: #2a2a2a;
            padding: 20px;
            border-radius: 10px;
            margin: 20px auto;
            max-width: 600px;
            text-align: left;
        }
    </style>
</head>
<body>
    <h1>$StatusCode</h1>
    <h2>$Message</h2>
"@
        
        if (-not [string]::IsNullOrEmpty($Details)) {
            $html += @"
    <div class="details">
        <strong>Details:</strong><br>
        $Details
    </div>
"@
        }
        
        $html += @"
</body>
</html>
"@
        
        Send-FVHtmlResponse -Response $Response -Html $html -StatusCode $StatusCode
        
    } catch {
        Write-Error "Fehler beim Senden der Error-Response: $($_.Exception.Message)"
        throw
    }
}