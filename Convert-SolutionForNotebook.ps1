#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$UnpackedFolder,

    [Parameter(Mandatory=$true)]
    [string]$OutputFolder,

    [int]$RawYamlLineCap = 200
)

$ErrorActionPreference = 'Stop'

function Get-Xml {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return [xml](Get-Content -Path $Path -Raw -Encoding UTF8) } catch { return $null }
}

function Get-ChildText {
    param($Node,[string]$Name)
    if ($null -eq $Node) { return $null }
    $c = $Node.SelectSingleNode($Name)
    if ($c) { return $c.InnerText } else { return $null }
}

function Get-Attr {
    param($Node,[string]$Name)
    if ($null -eq $Node) { return $null }
    if ($Node.HasAttribute($Name)) { return $Node.GetAttribute($Name) } else { return $null }
}

function Read-Tables {
    param([string]$Root)
    $tables = New-Object System.Collections.ArrayList
    $columns = New-Object System.Collections.ArrayList
    $entitiesDir = Join-Path $Root 'Entities'
    if (-not (Test-Path $entitiesDir)) { return @{ Tables=$tables; Columns=$columns } }
    foreach ($dir in Get-ChildItem -Path $entitiesDir -Directory) {
        $xml = Get-Xml (Join-Path $dir.FullName 'Entity.xml')
        if (-not $xml) { continue }
        $entNode = $xml.SelectSingleNode("//EntityInfo/entity")
        if (-not $entNode) { continue }
        $logical = Get-Attr $entNode 'Name'
        if (-not $logical) { $logical = $dir.Name }
        $dispNode = $entNode.SelectSingleNode("LocalizedNames/LocalizedName")
        $display = if ($dispNode) { Get-Attr $dispNode 'description' } else { $logical }
        if (-not $display) { $display = $logical }

        $colCount = 0
        foreach ($a in $xml.SelectNodes("//EntityInfo/entity/attributes/attribute")) {
            $colLogical = Get-ChildText $a 'LogicalName'
            if (-not $colLogical) { $colLogical = Get-Attr $a 'PhysicalName' }
            if (-not $colLogical) { continue }
            $type = Get-ChildText $a 'Type'
            $req  = Get-ChildText $a 'RequiredLevel'
            $dn = $a.SelectSingleNode("displaynames/displayname")
            $colDisplay = if ($dn) { Get-Attr $dn 'description' } else { $colLogical }
            if (-not $colDisplay) { $colDisplay = $colLogical }
            $optionText = ''
            $optNodes = $a.SelectNodes("optionset/options/option")
            if ($optNodes -and $optNodes.Count -gt 0) {
                $parts = New-Object System.Collections.ArrayList
                foreach ($o in $optNodes) {
                    $val = Get-Attr $o 'value'
                    $lbl = $o.SelectSingleNode("labels/label")
                    $lblText = if ($lbl) { Get-Attr $lbl 'description' } else { '' }
                    [void]$parts.Add("$val=$lblText")
                }
                $optionText = ($parts -join '; ')
            }
            [void]$columns.Add([pscustomobject]@{
                Table=$logical; Logical=$colLogical; Display=$colDisplay; Type=$type; Required=$req; Choices=$optionText
            })
            $colCount++
        }
        [void]$tables.Add([pscustomobject]@{ Logical=$logical; Display=$display; Columns=$colCount })
    }
    return @{ Tables=$tables; Columns=$columns }
}

function Read-Relationships {
    param([string]$Root)
    $rels = New-Object System.Collections.ArrayList
    $xml = Get-Xml (Join-Path $Root 'Other\Relationships.xml')
    if (-not $xml) { return $rels }
    foreach ($r in $xml.SelectNodes("//EntityRelationship")) {
        $name = Get-Attr $r 'Name'
        if (-not $name) { $name = Get-ChildText $r 'EntityRelationshipName' }
        $type = Get-ChildText $r 'EntityRelationshipType'
        if ($type -eq 'ManyToMany') {
            [void]$rels.Add([pscustomobject]@{
                Name=$name; Type=$type; Referencing=(Get-ChildText $r 'FirstEntityName'); Referenced=(Get-ChildText $r 'SecondEntityName'); ViaAttribute=''
            })
        } else {
            [void]$rels.Add([pscustomobject]@{
                Name=$name; Type=$type; Referencing=(Get-ChildText $r 'ReferencingEntityName'); Referenced=(Get-ChildText $r 'ReferencedEntityName'); ViaAttribute=(Get-ChildText $r 'ReferencingAttributeName')
            })
        }
    }
    return $rels
}

function Read-AppModules {
    param([string]$Root)
    $apps = New-Object System.Collections.ArrayList
    $dir = Join-Path $Root 'AppModules'
    if (-not (Test-Path $dir)) { return $apps }
    foreach ($appDir in Get-ChildItem -Path $dir -Directory) {
        $appXml = Get-Xml (Join-Path $appDir.FullName 'AppModule.xml')
        $unique = $appDir.Name
        $display = $appDir.Name
        if ($appXml) {
            $u = Get-ChildText $appXml.DocumentElement 'UniqueName'
            if ($u) { $unique = $u }
            $ln = $appXml.SelectSingleNode("//LocalizedNames/LocalizedName")
            if ($ln) { $d = Get-Attr $ln 'description'; if ($d) { $display = $d } }
        }
        $areas = New-Object System.Collections.ArrayList
        foreach ($xmlFile in Get-ChildItem -Path $appDir.FullName -Recurse -Filter *.xml) {
            $sm = Get-Xml $xmlFile.FullName
            if (-not $sm) { continue }
            if (-not $sm.SelectNodes("//Area")) { continue }
            foreach ($area in $sm.SelectNodes("//Area")) {
                $areaTitle = Get-Attr $area 'Title'
                if (-not $areaTitle) { $t = $area.SelectSingleNode("Titles/Title"); if ($t) { $areaTitle = Get-Attr $t 'Title' } }
                $groups = New-Object System.Collections.ArrayList
                foreach ($grp in $area.SelectNodes("Group")) {
                    $grpTitle = Get-Attr $grp 'Title'
                    if (-not $grpTitle) { $t = $grp.SelectSingleNode("Titles/Title"); if ($t) { $grpTitle = Get-Attr $t 'Title' } }
                    $subs = New-Object System.Collections.ArrayList
                    foreach ($sa in $grp.SelectNodes("SubArea")) {
                        $saTitle = Get-Attr $sa 'Title'
                        if (-not $saTitle) { $t = $sa.SelectSingleNode("Titles/Title"); if ($t) { $saTitle = Get-Attr $t 'Title' } }
                        [void]$subs.Add([pscustomobject]@{ Title=$saTitle; Entity=(Get-Attr $sa 'Entity'); Url=(Get-Attr $sa 'Url') })
                    }
                    [void]$groups.Add([pscustomobject]@{ Title=$grpTitle; SubAreas=$subs })
                }
                [void]$areas.Add([pscustomobject]@{ Title=$areaTitle; Groups=$groups })
            }
        }
        [void]$apps.Add([pscustomobject]@{ Unique=$unique; Display=$display; Areas=$areas })
    }
    return $apps
}

function Read-Bots {
    param([string]$Root,[int]$LineCap)
    $bots = New-Object System.Collections.ArrayList
    $candidateDirs = Get-ChildItem -Path $Root -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(bots|botcomponents)$' }
    $yamlFiles = New-Object System.Collections.ArrayList
    if ($candidateDirs) {
        foreach ($d in $candidateDirs) {
            foreach ($f in Get-ChildItem -Path $d.FullName -Recurse -Include *.yaml,*.yml -ErrorAction SilentlyContinue) { [void]$yamlFiles.Add($f) }
        }
    }
    if ($yamlFiles.Count -eq 0) {
        foreach ($f in Get-ChildItem -Path $Root -Recurse -Include *.yaml,*.yml -ErrorAction SilentlyContinue) { [void]$yamlFiles.Add($f) }
    }
    foreach ($f in $yamlFiles) {
        $lines = Get-Content -Path $f.FullName -Encoding UTF8
        $displayName = ($f.BaseName -replace '\.topic$','')
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*displayName:\s*(.+)$') { $displayName = $matches[1].Trim().Trim('"').Trim("'"); break }
        }
        $triggers = New-Object System.Collections.ArrayList
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*triggerQueries:\s*$') {
                for ($j=$i+1; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match '^\s*-\s*(.+)$') { [void]$triggers.Add(($matches[1].Trim().Trim('"').Trim("'"))) }
                    elseif ($lines[$j] -match '^\s*$') { continue } else { break }
                }
            }
        }
        $knowledge = New-Object System.Collections.ArrayList
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)(knowledgeSources|searchEnabled|dataSource|sharePointSearch|publicWebSearch)') { [void]$knowledge.Add($lines[$i].Trim()) }
        }
        $raw = if ($lines.Count -gt $LineCap) { ($lines[0..($LineCap-1)] -join "`r`n") + "`r`n... [truncated $($lines.Count - $LineCap) lines]" } else { ($lines -join "`r`n") }
        [void]$bots.Add([pscustomobject]@{ File=$f.Name; DisplayName=$displayName; Triggers=$triggers; Knowledge=$knowledge; Raw=$raw })
    }
    return $bots
}

function Read-Inventory {
    param([string]$Root)
    $sol = Get-Xml (Join-Path $Root 'Other\Solution.xml')
    $cust = Get-Xml (Join-Path $Root 'Other\Customizations.xml')
    $man = if ($sol) { $sol.SelectSingleNode("//SolutionManifest") } else { $null }
    $pub = if ($man) { $man.SelectSingleNode("Publisher") } else { $null }
    $inv = [ordered]@{
        UniqueName = if ($man) { Get-ChildText $man 'UniqueName' } else { '' }
        Version    = if ($man) { Get-ChildText $man 'Version' } else { '' }
        Managed    = if ($man) { Get-ChildText $man 'Managed' } else { '' }
        Publisher  = if ($pub) { Get-ChildText $pub 'UniqueName' } else { '' }
        Prefix     = if ($pub) { Get-ChildText $pub 'CustomizationPrefix' } else { '' }
    }
    function Count-Folder($p) { if (Test-Path $p) { (Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue).Count } else { 0 } }
    $inv.TableCount = Count-Folder (Join-Path $Root 'Entities')
    $inv.AppCount   = Count-Folder (Join-Path $Root 'AppModules')
    $wfDir = Join-Path $Root 'Workflows'
    $inv.WorkflowCount = if (Test-Path $wfDir) { (Get-ChildItem -Path $wfDir -Filter *.json -ErrorAction SilentlyContinue).Count } else { 0 }
    $wrDir = Join-Path $Root 'WebResources'
    $inv.WebResourceCount = if (Test-Path $wrDir) { (Get-ChildItem -Path $wrDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne '.data.xml' }).Count } else { 0 }
    $inv.GlobalChoiceCount  = if ($cust) { $cust.SelectNodes("//optionsets/optionset").Count } else { 0 }
    $inv.ConnectionRefCount = if ($cust) { $cust.SelectNodes("//connectionreferences/connectionreference").Count } else { 0 }
    $inv.EnvVariableCount   = if ($cust) { $cust.SelectNodes("//environmentvariabledefinitions/environmentvariabledefinition").Count } else { 0 }
    return $inv
}

function Save-Text {
    param([System.Collections.ArrayList]$Lines,[string]$Path)
    Set-Content -Path $Path -Value ($Lines -join "`r`n") -Encoding UTF8
}

if (-not (Test-Path $UnpackedFolder)) { throw "UnpackedFolder not found: $UnpackedFolder" }
$root = (Resolve-Path $UnpackedFolder).Path
if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$OutputFolder = (Resolve-Path $OutputFolder).Path
Write-Host "Source root: $root"

$tablesResult = Read-Tables -Root $root
$tables  = $tablesResult.Tables
$columns = $tablesResult.Columns
$rels    = Read-Relationships -Root $root
$apps    = Read-AppModules -Root $root
$bots    = Read-Bots -Root $root -LineCap $RawYamlLineCap
$inv     = Read-Inventory -Root $root

Write-Host ("Parsed: {0} tables, {1} columns, {2} relationships, {3} apps, {4} agent files" -f $tables.Count,$columns.Count,$rels.Count,$apps.Count,$bots.Count)

$tablesCsv = Join-Path $OutputFolder '01_Tables.csv'
$columnsCsv = Join-Path $OutputFolder '02_Columns.csv'
$relsCsv = Join-Path $OutputFolder '03_Relationships.csv'
$invTxt = Join-Path $OutputFolder '04_ComponentInventory.txt'
$mdaTxt = Join-Path $OutputFolder '05_MDA_Specification.txt'
$agentTxt = Join-Path $OutputFolder '06_AgentDesign.txt'

$tables  | Export-Csv -Path $tablesCsv -NoTypeInformation -Encoding UTF8
$columns | Export-Csv -Path $columnsCsv -NoTypeInformation -Encoding UTF8
$rels    | Export-Csv -Path $relsCsv -NoTypeInformation -Encoding UTF8

$L = New-Object System.Collections.ArrayList
[void]$L.Add('SOLUTION COMPONENT INVENTORY')
[void]$L.Add('============================')
[void]$L.Add('')
[void]$L.Add('Solution')
[void]$L.Add('--------')
[void]$L.Add("Unique name: $($inv.UniqueName)")
[void]$L.Add("Version: $($inv.Version)")
[void]$L.Add("Publisher: $($inv.Publisher)  (prefix: $($inv.Prefix))")
[void]$L.Add("Managed: $($inv.Managed)")
[void]$L.Add('')
[void]$L.Add('Component counts')
[void]$L.Add('----------------')
[void]$L.Add("Tables: $($inv.TableCount)")
[void]$L.Add("Model-driven apps: $($inv.AppCount)")
[void]$L.Add("Cloud flows / workflows: $($inv.WorkflowCount)")
[void]$L.Add("Web resources: $($inv.WebResourceCount)")
[void]$L.Add("Global choices: $($inv.GlobalChoiceCount)")
[void]$L.Add("Connection references: $($inv.ConnectionRefCount)")
[void]$L.Add("Environment variables: $($inv.EnvVariableCount)")
[void]$L.Add('')
[void]$L.Add('Tables')
[void]$L.Add('------')
if ($tables.Count -eq 0) { [void]$L.Add('None found.') }
foreach ($t in $tables) { [void]$L.Add("- $($t.Display)  ($($t.Logical), $($t.Columns) columns)") }
[void]$L.Add('')
[void]$L.Add('Model-driven apps')
[void]$L.Add('-----------------')
if ($apps.Count -eq 0) { [void]$L.Add('None found.') }
foreach ($a in $apps) { [void]$L.Add("- $($a.Display)  ($($a.Unique))") }
[void]$L.Add('')
[void]$L.Add('Agents')
[void]$L.Add('------')
if ($bots.Count -eq 0) { [void]$L.Add('None found.') }
foreach ($b in $bots) { [void]$L.Add("- $($b.DisplayName)  ($($b.File))") }
Save-Text -Lines $L -Path $invTxt

$L = New-Object System.Collections.ArrayList
[void]$L.Add('MODEL-DRIVEN APP SPECIFICATION')
[void]$L.Add('==============================')
[void]$L.Add('')
if ($apps.Count -eq 0) { [void]$L.Add('No model-driven apps found in this solution.') }
foreach ($a in $apps) {
    [void]$L.Add("APP: $($a.Display)")
    [void]$L.Add("Unique name: $($a.Unique)")
    [void]$L.Add('')
    if ($a.Areas.Count -eq 0) { [void]$L.Add('No site map found for this app.') }
    $surfaced = New-Object System.Collections.ArrayList
    foreach ($area in $a.Areas) {
        [void]$L.Add("  Area: $($area.Title)")
        foreach ($grp in $area.Groups) {
            [void]$L.Add("    Group: $($grp.Title)")
            foreach ($sa in $grp.SubAreas) {
                $label = $sa.Title; if (-not $label) { $label = $sa.Entity }
                $target = if ($sa.Entity) { "table: $($sa.Entity)" } elseif ($sa.Url) { "url: $($sa.Url)" } else { '' }
                [void]$L.Add("      - $label  ($target)")
                if ($sa.Entity -and -not $surfaced.Contains($sa.Entity)) { [void]$surfaced.Add($sa.Entity) }
            }
        }
    }
    [void]$L.Add('')
    [void]$L.Add('  Tables surfaced by this app:')
    if ($surfaced.Count -eq 0) { [void]$L.Add('  None resolved from site map.') }
    foreach ($e in $surfaced) { [void]$L.Add("  - $e") }
    [void]$L.Add('')
}
Save-Text -Lines $L -Path $mdaTxt

$L = New-Object System.Collections.ArrayList
[void]$L.Add('AGENT DESIGN')
[void]$L.Add('============')
[void]$L.Add('')
if ($bots.Count -eq 0) { [void]$L.Add('No agent topic files found in this solution.') }
foreach ($b in $bots) {
    [void]$L.Add("TOPIC: $($b.DisplayName)")
    [void]$L.Add("Source file: $($b.File)")
    [void]$L.Add('')
    [void]$L.Add('  Trigger phrases:')
    if ($b.Triggers.Count -eq 0) { [void]$L.Add('  None detected.') }
    foreach ($t in $b.Triggers) { [void]$L.Add("  - $t") }
    if ($b.Knowledge.Count -gt 0) {
        [void]$L.Add('')
        [void]$L.Add('  Knowledge / search references:')
        foreach ($k in $b.Knowledge) { [void]$L.Add("  - $k") }
    }
    [void]$L.Add('')
    [void]$L.Add('  Raw topic definition:')
    [void]$L.Add('  ---------------------')
    foreach ($line in ($b.Raw -split "`r`n")) { [void]$L.Add("  $line") }
    [void]$L.Add('')
}
Save-Text -Lines $L -Path $agentTxt

Write-Host ''
Write-Host 'Done. Files written:'
Write-Host "  $tablesCsv"
Write-Host "  $columnsCsv"
Write-Host "  $relsCsv"
Write-Host "  $invTxt"
Write-Host "  $mdaTxt"
Write-Host "  $agentTxt"
