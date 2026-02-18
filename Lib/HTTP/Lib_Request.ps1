<#
.SYNOPSIS
HTTP-Request Handling für Foto_Viewer

.DESCRIPTION
Vereinfacht das Lesen von Request-Daten:
- Query-Parameter aus URL
- POST-Body lesen
- Form-Daten parsen
- URL-Dekodierung

Funktionen:
- Get-FVQueryParam: Query-Parameter aus URL holen
- Read-FVRequestBody: POST-Body als String lesen
- Get-FVFormData: Form-Daten parsen (application/x-www-form-urlencoded)
- ConvertFrom-FVUrlEncoded: URL-Dekodierung

.EXAMPLE
# Query-Parameter
$path = Get-FVQueryParam -Request $request -Name "path"
# URL: /api/img?path=2024/photo.jpg
# → $path = "2024/photo.jpg"

.EXAMPLE
# POST-Body
$json = Read-FVRequestBody -Request $request
$data = $json | ConvertFrom-Json

.EXAMPLE
# Form-Daten
$formData = Get-FVFormData -Request $request
# POST: name=test&value=42
# → $formData = @{ name="test"; value=42 }

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

function Get-FVQueryParam {
    <#
    .SYNOPSIS
    Holt Query-Parameter aus URL
    
    .DESCRIPTION
    Liest Query-Parameter aus Request-URL.
    Unterstützt URL-Dekodierung.
    
    URL-Format: /path?key1=value1&key2=value2
    
    .PARAMETER Request
    HttpListenerRequest-Objekt
    
    .PARAMETER Name
    Parameter-Name (z.B. "path", "id", "filter")
    
    .PARAMETER Default
    Optional: Default-Wert wenn Parameter nicht existiert
    
    .PARAMETER UrlDecode
    Optional: URL-Dekodierung durchführen (Default: $true)
    Konvertiert %20 → Space, %2F → /, etc.
    
    .EXAMPLE
    $path = Get-FVQueryParam -Request $request -Name "path"
    # URL: /api/img?path=2024/photo.jpg
    # → $path = "2024/photo.jpg"
    
    .EXAMPLE
    # Mit Default-Wert
    $page = Get-FVQueryParam -Request $request -Name "page" -Default 1
    # URL: /api/list (ohne page Parameter)
    # → $page = 1
    
    .EXAMPLE
    # Mit URL-Dekodierung
    $search = Get-FVQueryParam -Request $request -Name "q"
    # URL: /search?q=Hello%20World
    # → $search = "Hello World"
    
    .OUTPUTS
    String - Parameter-Wert (oder Default)
    
    .NOTES
    Gibt $null zurück wenn Parameter nicht existiert und kein Default angegeben
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerRequest]$Request,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [object]$Default,
        
        [Parameter()]
        [bool]$UrlDecode = $true
    )
    
    try {
        # Query-String parsen
        $query = $Request.Url.Query
        
        if ([string]::IsNullOrEmpty($query)) {
            # Keine Query-Parameter
            if ($PSBoundParameters.ContainsKey('Default')) {
                return $Default
            }
            return $null
        }
        
        # Leading '?' entfernen
        if ($query.StartsWith('?')) {
            $query = $query.Substring(1)
        }
        
        # Parameter parsen (manuell, ohne System.Web)
        $params = @{}
        $pairs = $query -split '&'
        
        foreach ($pair in $pairs) {
            if ([string]::IsNullOrWhiteSpace($pair)) {
                continue
            }
            
            $keyValue = $pair -split '=', 2
            $key = $keyValue[0]
            $value = if ($keyValue.Length -gt 1) { $keyValue[1] } else { "" }
            
            # URL-Dekodierung
            if ($UrlDecode) {
                $key = ConvertFrom-FVUrlEncoded -Text $key
                $value = ConvertFrom-FVUrlEncoded -Text $value
            }
            
            $params[$key] = $value
        }
        
        # Gesuchten Parameter zurückgeben
        if ($params.ContainsKey($Name)) {
            $result = $params[$Name]
            Write-Verbose "Query-Parameter '$Name' = '$result'"
            return $result
        }
        
        # Parameter nicht gefunden
        if ($PSBoundParameters.ContainsKey('Default')) {
            Write-Verbose "Query-Parameter '$Name' nicht gefunden, verwende Default: $Default"
            return $Default
        }
        
        Write-Verbose "Query-Parameter '$Name' nicht gefunden"
        return $null
        
    } catch {
        Write-Error "Fehler beim Lesen des Query-Parameters '$Name': $($_.Exception.Message)"
        throw
    }
}

function Read-FVRequestBody {
    <#
    .SYNOPSIS
    Liest POST-Body als String
    
    .DESCRIPTION
    Liest kompletten Request-Body (POST/PUT) als UTF8-String.
    
    Typische Verwendung:
    - JSON-Daten: ConvertFrom-Json
    - Form-Daten: Get-FVFormData
    - XML-Daten: [xml]$body
    
    .PARAMETER Request
    HttpListenerRequest-Objekt
    
    .EXAMPLE
    $body = Read-FVRequestBody -Request $request
    $data = $body | ConvertFrom-Json
    Write-Host "Name: $($data.name)"
    
    .EXAMPLE
    # Mit Error-Handling
    try {
        $body = Read-FVRequestBody -Request $request
        Write-Host "Body Länge: $($body.Length) Zeichen"
    } catch {
        Write-Host "Kein Body vorhanden"
    }
    
    .OUTPUTS
    String - Request-Body als UTF8-String
    
    .NOTES
    Gibt leeren String zurück wenn kein Body vorhanden.
    Stream wird automatisch geschlossen.
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerRequest]$Request
    )
    
    try {
        # Content-Length prüfen
        if ($Request.ContentLength64 -le 0) {
            Write-Verbose "Kein Request-Body (ContentLength = 0)"
            return ""
        }
        
        Write-Verbose "Lese Request-Body ($($Request.ContentLength64) bytes)..."
        
        # Stream lesen
        $reader = [System.IO.StreamReader]::new(
            $Request.InputStream,
            [System.Text.Encoding]::UTF8
        )
        
        try {
            $body = $reader.ReadToEnd()
            Write-Verbose "Request-Body gelesen: $($body.Length) Zeichen"
            return $body
            
        } finally {
            $reader.Close()
        }
        
    } catch {
        Write-Error "Fehler beim Lesen des Request-Body: $($_.Exception.Message)"
        throw
    }
}

function Get-FVFormData {
    <#
    .SYNOPSIS
    Parst Form-Daten aus POST-Request
    
    .DESCRIPTION
    Parst application/x-www-form-urlencoded Daten aus POST-Body.
    
    Format: key1=value1&key2=value2&key3=value3
    
    Gibt Hashtable mit Key-Value-Paaren zurück.
    
    .PARAMETER Request
    HttpListenerRequest-Objekt
    
    .PARAMETER UrlDecode
    Optional: URL-Dekodierung durchführen (Default: $true)
    
    .EXAMPLE
    $formData = Get-FVFormData -Request $request
    # POST: name=John&age=30&city=Vienna
    # → $formData = @{ name="John"; age="30"; city="Vienna" }
    
    Write-Host "Name: $($formData['name'])"
    Write-Host "Age: $($formData['age'])"
    
    .EXAMPLE
    # Mit URL-Dekodierung
    $formData = Get-FVFormData -Request $request
    # POST: message=Hello%20World&email=test%40example.com
    # → $formData = @{ message="Hello World"; email="test@example.com" }
    
    .OUTPUTS
    Hashtable - Key-Value-Paare der Form-Daten
    
    .NOTES
    Gibt leere Hashtable zurück wenn kein Body vorhanden.
    Nur für application/x-www-form-urlencoded, nicht für multipart/form-data.
    #>
    
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Net.HttpListenerRequest]$Request,
        
        [Parameter()]
        [bool]$UrlDecode = $true
    )
    
    try {
        # Body lesen
        $body = Read-FVRequestBody -Request $Request
        
        if ([string]::IsNullOrWhiteSpace($body)) {
            Write-Verbose "Kein Form-Body vorhanden"
            return @{}
        }
        
        Write-Verbose "Parse Form-Data: $($body.Length) Zeichen"
        
        # Form-Daten parsen
        $formData = @{}
        $pairs = $body -split '&'
        
        foreach ($pair in $pairs) {
            if ([string]::IsNullOrWhiteSpace($pair)) {
                continue
            }
            
            $keyValue = $pair -split '=', 2
            $key = $keyValue[0]
            $value = if ($keyValue.Length -gt 1) { $keyValue[1] } else { "" }
            
            # URL-Dekodierung
            if ($UrlDecode) {
                $key = ConvertFrom-FVUrlEncoded -Text $key
                $value = ConvertFrom-FVUrlEncoded -Text $value
            }
            
            $formData[$key] = $value
            Write-Verbose "Form-Data: '$key' = '$value'"
        }
        
        Write-Verbose "Form-Data geparst: $($formData.Count) Felder"
        return $formData
        
    } catch {
        Write-Error "Fehler beim Parsen der Form-Daten: $($_.Exception.Message)"
        throw
    }
}

function ConvertFrom-FVUrlEncoded {
    <#
    .SYNOPSIS
    URL-Dekodierung
    
    .DESCRIPTION
    Konvertiert URL-encodierte Strings zurück zu normalem Text.
    
    Konvertierungen:
    - %20 → Space
    - %2F → /
    - %3A → :
    - + → Space
    - etc.
    
    .PARAMETER Text
    URL-encodierter Text
    
    .EXAMPLE
    $decoded = ConvertFrom-FVUrlEncoded -Text "Hello%20World"
    # → "Hello World"
    
    .EXAMPLE
    $decoded = ConvertFrom-FVUrlEncoded -Text "path%2F2024%2Fphoto.jpg"
    # → "path/2024/photo.jpg"
    
    .EXAMPLE
    $decoded = ConvertFrom-FVUrlEncoded -Text "search+term"
    # → "search term"
    
    .OUTPUTS
    String - Dekodierter Text
    
    .NOTES
    Verwendet .NET UrlDecode für korrekte Konvertierung
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )
    
    try {
        if ([string]::IsNullOrEmpty($Text)) {
            return ""
        }
        
        # + zu Space konvertieren (URL-Encoding für Space in Forms)
        $Text = $Text -replace '\+', ' '
        
        # URL-Dekodierung (.NET)
        $decoded = [System.Uri]::UnescapeDataString($Text)
        
        Write-Verbose "URL-Dekodierung: '$Text' → '$decoded'"
        return $decoded
        
    } catch {
        Write-Verbose "URL-Dekodierung fehlgeschlagen, gebe Original zurück: $($_.Exception.Message)"
        return $Text
    }
}

function ConvertTo-FVUrlEncoded {
    <#
    .SYNOPSIS
    URL-Enkodierung
    
    .DESCRIPTION
    Konvertiert Text zu URL-encodiertem String.
    
    Konvertierungen:
    - Space → %20
    - / → %2F
    - : → %3A
    - etc.
    
    .PARAMETER Text
    Text zum Enkodieren
    
    .EXAMPLE
    $encoded = ConvertTo-FVUrlEncoded -Text "Hello World"
    # → "Hello%20World"
    
    .EXAMPLE
    $encoded = ConvertTo-FVUrlEncoded -Text "path/2024/photo.jpg"
    # → "path%2F2024%2Fphoto.jpg"
    
    .OUTPUTS
    String - Enkodierter Text
    
    .NOTES
    Nützlich für URL-Generierung
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )
    
    try {
        if ([string]::IsNullOrEmpty($Text)) {
            return ""
        }
        
        # URL-Enkodierung (.NET)
        $encoded = [System.Uri]::EscapeDataString($Text)
        
        Write-Verbose "URL-Enkodierung: '$Text' → '$encoded'"
        return $encoded
        
    } catch {
        Write-Verbose "URL-Enkodierung fehlgeschlagen: $($_.Exception.Message)"
        return $Text
    }
}