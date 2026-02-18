<#
.SYNOPSIS
Template-Engine für Foto_Viewer

.DESCRIPTION
Lädt HTML/CSS/JS aus separaten Files (nicht Here-Strings!).
Ersetzt Variablen und rendert Templates.

Funktionen:
- Invoke-FVTemplate: Template laden und rendern
- Get-FVPartial: Partial-Template laden
- Get-FVAssetUrl: Asset-URL mit Cache-Busting
- Resolve-FVTemplateVariables: Variablen ersetzen

Features:
- Template-Verzeichnis: templates/
- Variable-Replacement: {{variable}}
- Nested Variables: {{user.name}}
- Partials: {{> header}}
- Cache-Busting für Assets

.EXAMPLE
# Template rendern
$html = Invoke-FVTemplate -Name "gallery" -Data @{
    title = "My Photos"
    items = $mediaList
}

.EXAMPLE
# Mit Partials
$html = Invoke-FVTemplate -Name "page" -Data @{
    content = "Hello World"
}
# page.html enthält: {{> header}} {{content}} {{> footer}}

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
# MODULE-LEVEL VARIABLES
# ============================================================================

$script:FVTemplateCache = @{}
$script:FVPartialCache = @{}

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

function Get-TemplateDirectory {
    <#
    .SYNOPSIS
    Ermittelt Template-Verzeichnis
    
    .OUTPUTS
    String - Pfad zu templates/
    
    .NOTES
    Internal Helper
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $scriptRoot = $PSScriptRoot
        $libDir = Split-Path $scriptRoot -Parent
        $projectRoot = Split-Path $libDir -Parent
        $templateDir = Join-Path $projectRoot "templates"
        
        if (-not (Test-Path -LiteralPath $templateDir)) {
            throw "Template-Verzeichnis nicht gefunden: $templateDir"
        }
        
        return $templateDir
        
    } catch {
        Write-Error "Fehler beim Ermitteln des Template-Verzeichnisses: $($_.Exception.Message)"
        throw
    }
}

function Get-NestedValue {
    <#
    .SYNOPSIS
    Holt verschachtelten Wert aus Hashtable/Object
    
    .DESCRIPTION
    Unterstützt Dot-Notation: user.name → $data['user']['name']
    
    .PARAMETER Data
    Hashtable oder PSCustomObject
    
    .PARAMETER Path
    Pfad mit Dot-Notation
    
    .EXAMPLE
    Get-NestedValue -Data @{ user = @{ name = "John" } } -Path "user.name"
    # → "John"
    
    .OUTPUTS
    Object - Wert oder $null
    
    .NOTES
    Internal Helper
    #>
    
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object]$Data,
        
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        $parts = $Path -split '\.'
        $current = $Data
        
        foreach ($part in $parts) {
            if ($null -eq $current) {
                return $null
            }
            
            # Hashtable
            if ($current -is [hashtable]) {
                if ($current.ContainsKey($part)) {
                    $current = $current[$part]
                } else {
                    return $null
                }
            }
            # PSCustomObject
            elseif ($current.PSObject.Properties[$part]) {
                $current = $current.$part
            }
            else {
                return $null
            }
        }
        
        return $current
        
    } catch {
        Write-Verbose "Fehler beim Abrufen von '$Path': $($_.Exception.Message)"
        return $null
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Get-FVPartial {
    <#
    .SYNOPSIS
    Lädt Partial-Template
    
    .DESCRIPTION
    Lädt HTML-Fragment aus templates/partials/
    
    Cached für Performance.
    
    .PARAMETER Name
    Partial-Name (ohne .html)
    
    .PARAMETER NoCache
    Optional: Cache ignorieren
    
    .EXAMPLE
    $header = Get-FVPartial -Name "header"
    
    .EXAMPLE
    # Ohne Cache
    $header = Get-FVPartial -Name "header" -NoCache
    
    .OUTPUTS
    String - HTML-Inhalt
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [switch]$NoCache
    )
    
    try {
        # Cache prüfen
        if (-not $NoCache -and $script:FVPartialCache.ContainsKey($Name)) {
            Write-Verbose "Partial aus Cache: $Name"
            return $script:FVPartialCache[$Name]
        }
        
        # Partial-Pfad
        $templateDir = Get-TemplateDirectory
        $partialPath = Join-Path $templateDir "partials\$Name.html"
        
        if (-not (Test-Path -LiteralPath $partialPath)) {
            throw "Partial nicht gefunden: $partialPath"
        }
        
        Write-Verbose "Lade Partial: $Name"
        
        # Laden
        $content = Get-Content -LiteralPath $partialPath -Raw -Encoding UTF8
        
        # Cache
        if (-not $NoCache) {
            $script:FVPartialCache[$Name] = $content
        }
        
        return $content
        
    } catch {
        Write-Error "Fehler beim Laden des Partials '$Name': $($_.Exception.Message)"
        throw
    }
}

function Resolve-FVTemplateVariables {
    <#
    .SYNOPSIS
    Ersetzt Variablen im Template
    
    .DESCRIPTION
    Ersetzt {{variable}} mit Werten aus Data.
    Unterstützt:
    - Einfache Variablen: {{name}}
    - Verschachtelt: {{user.name}}
    - Arrays (JSON): {{items}}
    
    .PARAMETER Template
    Template-String mit {{variables}}
    
    .PARAMETER Data
    Hashtable mit Variablen
    
    .EXAMPLE
    $html = Resolve-FVTemplateVariables -Template "Hello {{name}}" -Data @{ name = "John" }
    # → "Hello John"
    
    .EXAMPLE
    # Verschachtelt
    $html = Resolve-FVTemplateVariables -Template "{{user.name}}" -Data @{ 
        user = @{ name = "John" } 
    }
    # → "John"
    
    .OUTPUTS
    String - Prozessiertes Template
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Template,
        
        [Parameter(Mandatory)]
        [hashtable]$Data
    )
    
    try {
        if ([string]::IsNullOrEmpty($Template)) {
            return ""
        }
        
        $result = $Template
        
        # Finde alle {{variables}}
        $matches = [regex]::Matches($result, '\{\{([^}]+)\}\}')
        
        foreach ($match in $matches) {
            $placeholder = $match.Value           # {{name}}
            $varName = $match.Groups[1].Value.Trim()  # name
            
            # Wert holen (unterstützt Dot-Notation)
            $value = Get-NestedValue -Data $Data -Path $varName
            
            if ($null -eq $value) {
                Write-Verbose "Variable nicht gefunden: $varName"
                $replacement = ""
            }
            elseif ($value -is [array] -or $value -is [System.Collections.IEnumerable]) {
                # Array → JSON
                $replacement = $value | ConvertTo-Json -Compress -Depth 10
            }
            elseif ($value -is [hashtable] -or $value -is [PSCustomObject]) {
                # Object → JSON
                $replacement = $value | ConvertTo-Json -Compress -Depth 10
            }
            else {
                # Primitive → String
                $replacement = $value.ToString()
            }
            
            # Ersetzen
            $result = $result.Replace($placeholder, $replacement)
        }
        
        return $result
        
    } catch {
        Write-Error "Fehler beim Ersetzen der Template-Variablen: $($_.Exception.Message)"
        throw
    }
}

function Resolve-FVTemplatePartials {
    <#
    .SYNOPSIS
    Ersetzt Partials im Template
    
    .DESCRIPTION
    Ersetzt {{> partial-name}} mit Partial-Inhalt.
    
    .PARAMETER Template
    Template-String mit {{> partials}}
    
    .EXAMPLE
    $html = Resolve-FVTemplatePartials -Template "{{> header}} Content {{> footer}}"
    
    .OUTPUTS
    String - Template mit eingefügten Partials
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Template
    )
    
    try {
        if ([string]::IsNullOrEmpty($Template)) {
            return ""
        }
        
        $result = $Template
        
        # Finde alle {{> partial}}
        $matches = [regex]::Matches($result, '\{\{>\s*([^}]+)\s*\}\}')
        
        foreach ($match in $matches) {
            $placeholder = $match.Value           # {{> header}}
            $partialName = $match.Groups[1].Value.Trim()  # header
            
            Write-Verbose "Lade Partial: $partialName"
            
            # Partial laden
            try {
                $partialContent = Get-FVPartial -Name $partialName
                $result = $result.Replace($placeholder, $partialContent)
            } catch {
                Write-Verbose "Partial nicht gefunden: $partialName"
                $result = $result.Replace($placeholder, "<!-- Partial '$partialName' not found -->")
            }
        }
        
        return $result
        
    } catch {
        Write-Error "Fehler beim Ersetzen der Partials: $($_.Exception.Message)"
        throw
    }
}

function Get-FVAssetUrl {
    <#
    .SYNOPSIS
    Generiert Asset-URL mit Cache-Busting
    
    .DESCRIPTION
    Gibt relative URL zu CSS/JS mit optionalem Versionierungs-Parameter.
    
    .PARAMETER Path
    Asset-Pfad relativ zu templates/ (z.B. "css/style.css")
    
    .PARAMETER WithCacheBust
    Optional: Fügt ?v=timestamp für Cache-Busting hinzu
    
    .EXAMPLE
    $url = Get-FVAssetUrl -Path "css/style.css"
    # → "/assets/css/style.css"
    
    .EXAMPLE
    # Mit Cache-Busting
    $url = Get-FVAssetUrl -Path "js/app.js" -WithCacheBust
    # → "/assets/js/app.js?v=1708284000"
    
    .OUTPUTS
    String - Relative URL
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter()]
        [switch]$WithCacheBust
    )
    
    try {
        # URL normalisieren (Forward-Slashes)
        $normalizedPath = $Path -replace '\\', '/'
        
        # /assets/ Prefix
        $url = "/assets/$normalizedPath"
        
        # Cache-Busting
        if ($WithCacheBust) {
            $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $url = "$url`?v=$timestamp"
        }
        
        return $url
        
    } catch {
        Write-Error "Fehler beim Generieren der Asset-URL: $($_.Exception.Message)"
        throw
    }
}

function Invoke-FVTemplate {
    <#
    .SYNOPSIS
    Rendert Template mit Daten
    
    .DESCRIPTION
    Kompletter Rendering-Prozess:
    1. Template laden
    2. Partials einfügen
    3. Variablen ersetzen
    
    .PARAMETER Name
    Template-Name (ohne .html)
    
    .PARAMETER Data
    Hashtable mit Template-Daten
    
    .PARAMETER NoCache
    Optional: Template-Cache ignorieren
    
    .EXAMPLE
    $html = Invoke-FVTemplate -Name "gallery" -Data @{
        title = "My Photos"
        items = $mediaList
    }
    
    .EXAMPLE
    # Mit verschachtelten Daten
    $html = Invoke-FVTemplate -Name "page" -Data @{
        user = @{ name = "John"; role = "Admin" }
        stats = @{ total = 100; new = 5 }
    }
    
    .OUTPUTS
    String - Gerenderte HTML
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [hashtable]$Data,
        
        [Parameter()]
        [switch]$NoCache
    )
    
    try {
        Write-Verbose "Rendere Template: $Name"
        
        # Cache prüfen
        if (-not $NoCache -and $script:FVTemplateCache.ContainsKey($Name)) {
            Write-Verbose "Template aus Cache: $Name"
            $template = $script:FVTemplateCache[$Name]
        } else {
            # Template laden
            $templateDir = Get-TemplateDirectory
            $templatePath = Join-Path $templateDir "$Name.html"
            
            if (-not (Test-Path -LiteralPath $templatePath)) {
                throw "Template nicht gefunden: $templatePath"
            }
            
            Write-Verbose "Lade Template: $Name"
            $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
            
            # Cache
            if (-not $NoCache) {
                $script:FVTemplateCache[$Name] = $template
            }
        }
        
        # 1. Partials einfügen
        $template = Resolve-FVTemplatePartials -Template $template
        
        # 2. Variablen ersetzen
        $html = Resolve-FVTemplateVariables -Template $template -Data $Data
        
        Write-Verbose "Template gerendert: $($html.Length) Zeichen"
        
        return $html
        
    } catch {
        Write-Error "Fehler beim Rendern des Templates '$Name': $($_.Exception.Message)"
        throw
    }
}

function Clear-FVTemplateCache {
    <#
    .SYNOPSIS
    Löscht Template-Cache
    
    .DESCRIPTION
    Löscht gecachte Templates und Partials.
    Nützlich während Development.
    
    .EXAMPLE
    Clear-FVTemplateCache
    
    .NOTES
    Nach Clear werden Templates beim nächsten Aufruf neu geladen
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        $templateCount = $script:FVTemplateCache.Count
        $partialCount = $script:FVPartialCache.Count
        
        $script:FVTemplateCache = @{}
        $script:FVPartialCache = @{}
        
        Write-Verbose "Template-Cache gelöscht: $templateCount Templates, $partialCount Partials"
        
    } catch {
        Write-Error "Fehler beim Löschen des Template-Cache: $($_.Exception.Message)"
        throw
    }
}