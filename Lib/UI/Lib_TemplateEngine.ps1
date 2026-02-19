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
- Resolve-FVTemplateConditionals: {{#if}} Blöcke
- Resolve-FVTemplateLoops: {{#each}} Blöcke

Features:
- Template-Verzeichnis: templates/
- Variable-Replacement: {{variable}}
- Nested Variables: {{user.name}}
- Conditionals: {{#if condition}}...{{/if}}
- Loops: {{#each items}}...{{/each}}
- Partials: {{> header}}
- Cache-Busting für Assets

.EXAMPLE
# Template rendern
$html = Invoke-FVTemplate -Name "gallery" -Data @{
    title = "My Photos"
    items = $mediaList
}

.EXAMPLE
# Mit Conditionals und Loops
$html = Invoke-FVTemplate -Name "page" -Data @{
    showHeader = $true
    items = @(@{name="Item1"}, @{name="Item2"})
}

.NOTES
Autor: Herbert Schrotter
Version: 1.1.0
Erstellt: 2025-02-18
Aktualisiert: 2025-02-18
Projekt: Foto_Viewer

Changelog:
- v1.1.0: {{#if}} und {{#each}} Support hinzugefügt
- v1.0.0: Initiale Version mit Variablen und Partials

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

function Resolve-FVTemplateConditionals {
    <#
    .SYNOPSIS
    Verarbeitet {{#if}} Blöcke
    
    .DESCRIPTION
    Ersetzt {{#if variable}}...{{/if}} basierend auf Wahrheitswert.
    
    Logik:
    - null/empty/false → Block entfernen
    - Nicht-leere Strings → Block behalten
    - Arrays mit Elementen → Block behalten
    - true → Block behalten
    
    .PARAMETER Template
    Template-String
    
    .PARAMETER Data
    Daten-Hashtable
    
    .EXAMPLE
    $html = Resolve-FVTemplateConditionals -Template $template -Data @{
        showHeader = $true
        items = @(1,2,3)
    }
    
    .OUTPUTS
    String - Prozessiertes Template
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Template,
        
        [Parameter(Mandatory)]
        [hashtable]$Data
    )
    
    try {
        $result = $Template
        
        # Finde alle {{#if variable}}...{{/if}} Blöcke (mit Singleline für mehrzeilige Blöcke)
        $pattern = '\{\{#if\s+([^}]+)\}\}(.*?)\{\{/if\}\}'
        
        $maxIterations = 10
        $iteration = 0
        
        while ($result -match $pattern -and $iteration -lt $maxIterations) {
            $iteration++
            
            $matches = [regex]::Matches($result, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
            
            foreach ($match in $matches) {
                $fullBlock = $match.Value
                $varName = $match.Groups[1].Value.Trim()
                $content = $match.Groups[2].Value
                
                Write-Verbose "Conditional: $varName"
                
                # Wert holen
                $value = Get-NestedValue -Data $Data -Path $varName
                
                # Bedingung prüfen
                $condition = $false
                if ($null -ne $value) {
                    if ($value -is [bool]) {
                        $condition = $value
                    } elseif ($value -is [array]) {
                        $condition = $value.Count -gt 0
                    } elseif ($value -is [string]) {
                        $condition = -not [string]::IsNullOrEmpty($value)
                    } else {
                        $condition = $true
                    }
                }
                
                Write-Verbose "  Condition result: $condition"
                
                # Ersetzen
                if ($condition) {
                    # Content behalten, aber {{#if}} Tags entfernen
                    $result = $result.Replace($fullBlock, $content)
                } else {
                    # Ganzen Block entfernen
                    $result = $result.Replace($fullBlock, '')
                }
            }
        }
        
        return $result
        
    } catch {
        Write-Error "Fehler beim Verarbeiten der Conditionals: $($_.Exception.Message)"
        throw
    }
}

function Resolve-FVTemplateLoops {
    <#
    .SYNOPSIS
    Verarbeitet {{#each}} Blöcke
    
    .DESCRIPTION
    Ersetzt {{#each array}}...{{/each}} mit wiederholtem Content für jedes Array-Element.
    
    Im Loop-Block verfügbar:
    - {{this}} → Aktuelles Element (bei primitiven Arrays)
    - {{property}} → Property des aktuellen Objekts
    - {{@index}} → Index (0-basiert)
    
    .PARAMETER Template
    Template-String
    
    .PARAMETER Data
    Daten-Hashtable
    
    .EXAMPLE
    $html = Resolve-FVTemplateLoops -Template $template -Data @{
        items = @(
            @{name="Item1"; value=10},
            @{name="Item2"; value=20}
        )
    }
    # Template: {{#each items}}<div>{{name}}: {{value}}</div>{{/each}}
    # Result: <div>Item1: 10</div><div>Item2: 20</div>
    
    .OUTPUTS
    String - Prozessiertes Template
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Template,
        
        [Parameter(Mandatory)]
        [hashtable]$Data
    )
    
    try {
        $result = $Template
        
        # Finde alle {{#each array}}...{{/each}} Blöcke
        $pattern = '\{\{#each\s+([^}]+)\}\}(.*?)\{\{/each\}\}'
        
        $maxIterations = 10
        $iteration = 0
        
        while ($result -match $pattern -and $iteration -lt $maxIterations) {
            $iteration++
            
            $matches = [regex]::Matches($result, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
            
            foreach ($match in $matches) {
                $fullBlock = $match.Value
                $arrayName = $match.Groups[1].Value.Trim()
                $loopContent = $match.Groups[2].Value
                
                Write-Verbose "Loop: $arrayName"
                
                # Array holen
                $array = Get-NestedValue -Data $Data -Path $arrayName
                
                if ($null -eq $array) {
                    # Kein Array → Block entfernen
                    $result = $result.Replace($fullBlock, '')
                    continue
                }
                
                # Sicherstellen dass es ein Array ist
                if ($array -isnot [array]) {
                    $array = @($array)
                }
                
                Write-Verbose "  Array items: $($array.Count)"
                
                # Loop durchlaufen
                $output = ''
                for ($i = 0; $i -lt $array.Count; $i++) {
                    $item = $array[$i]
                    $itemContent = $loopContent
                    
                    # {{@index}} ersetzen
                    $itemContent = $itemContent -replace '\{\{@index\}\}', $i
                    
                    # {{this}} ersetzen (für primitive Arrays)
                    if ($item -is [string] -or $item -is [int] -or $item -is [double]) {
                        $itemContent = $itemContent -replace '\{\{this\}\}', $item
                    }
                    
                    # Properties ersetzen (für Objekt-Arrays)
                    if ($item -is [hashtable]) {
                        foreach ($key in $item.Keys) {
                            $value = $item[$key]
                            
                            # JSON für Arrays/Objects
                            if ($value -is [array] -or $value -is [hashtable]) {
                                $value = $value | ConvertTo-Json -Compress -Depth 10
                            }
                            
                            $placeholder = "{{$key}}"
                            $itemContent = $itemContent.Replace($placeholder, $value)
                        }
                    } elseif ($item -is [PSCustomObject]) {
                        foreach ($prop in $item.PSObject.Properties) {
                            $value = $prop.Value
                            
                            # JSON für Arrays/Objects
                            if ($value -is [array] -or $value -is [hashtable] -or $value -is [PSCustomObject]) {
                                $value = $value | ConvertTo-Json -Compress -Depth 10
                            }
                            
                            $placeholder = "{{$($prop.Name)}}"
                            $itemContent = $itemContent.Replace($placeholder, $value)
                        }
                    }
                    
                    $output += $itemContent
                }
                
                # Block durch Output ersetzen
                $result = $result.Replace($fullBlock, $output)
            }
        }
        
        return $result
        
    } catch {
        Write-Error "Fehler beim Verarbeiten der Loops: $($_.Exception.Message)"
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
        
        # Finde alle {{variables}} (KEINE #if, #each, >partial)
        $matches = [regex]::Matches($result, '\{\{(?!#|/|>)([^}]+)\}\}')
        
        foreach ($match in $matches) {
            $placeholder = $match.Value           # {{name}}
            $varName = $match.Groups[1].Value.Trim()  # name
            
            # Spezielle Variablen überspringen
            if ($varName -eq 'this' -or $varName -eq '@index') {
                continue
            }
            
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
                # Primitive → String direkt (keine Konvertierung!)
                if ($value -is [string]) {
                    $replacement = $value
                } else {
                    $replacement = $value.ToString()
                }
            }
            
            # Ersetzen (String.Replace ist sicher für Literale)
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
    3. Conditionals verarbeiten ({{#if}})
    4. Loops verarbeiten ({{#each}})
    5. Variablen ersetzen
    
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
        showHeader = $true
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
        
        # 2. Conditionals verarbeiten ({{#if}})
        $template = Resolve-FVTemplateConditionals -Template $template -Data $Data
        
        # 3. Loops verarbeiten ({{#each}})
        $template = Resolve-FVTemplateLoops -Template $template -Data $Data
        
        # 4. Variablen ersetzen
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