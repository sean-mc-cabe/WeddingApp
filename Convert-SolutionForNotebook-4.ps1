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
    if (-not $Path) { return $null }
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
    if ($Node.NodeType -ne [System.Xml.XmlNodeType]::Element) { return $null }
    if ($Node.HasAttribute($Name)) { return $Node.GetAttribute($Name) } else { return $null }
}

function Find-File {
    param([string]$Root,[string[]]$Candidates)
    foreach ($c in $Candidates) {
        $p = Join-Path $Root $c
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Parse-Entity {
    param($EntityEl)
    $entity = $EntityEl.SelectSingleNode("EntityInfo/entity")
    if (-not $entity) { return $null }
    $logical = Get-Attr $entity 'Name'
    if (-not $logical) { $logical = Get-ChildText $EntityEl 'Name' }
    if (-not $logical) { return $null }
    $dispNode = $entity.SelectSingleNode("LocalizedNames/LocalizedName")
    $display = if ($dispNode) { Get-Attr $dispNode 'description' } else { $logical }
    if (-not $display) { $display = $logical }
    $cols = New-Object System.Collections.ArrayList
    foreach ($a in $EntityEl.SelectNodes("EntityInfo/entity/attributes/attribute")) {
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
        [void]$cols.Add([pscustomobject]@{ Table=$logical; Logical=$colLogical; Display=$colDisplay; Type=$type; Required=$req; Choices=$optionText })
    }
    return [pscustomobject]@{
        Table=[pscustomobject]@{ Logical=$logical; Display=$display; Columns=$cols.Count }
        Columns=$cols
    }
}

function Read-Tables {
    param([string]$Root,$Cust)
    $tables = New-Object System.Collections.ArrayList
    $columns = New-Object System.Collections.ArrayList
    $entityEls = New-Object System.Collections.ArrayList
    $entitiesDir = Join-Path $Root 'Entities'
    if (Test-Path $entitiesDir) {
        foreach ($dir in Get-ChildItem -Path $entitiesDir -Directory) {
            $xml = Get-Xml (Join-Path $dir.FullName 'Entity.xml')
            if ($xml -and $xml.DocumentElement) { [void]$entityEls.Add($xml.DocumentElement) }
        }
    } elseif ($Cust) {
        foreach ($e in $Cust.DocumentElement.SelectNodes("Entities/Entity")) { [void]$entityEls.Add($e) }
    }
    foreach ($el in $entityEls) {
        $parsed = Parse-Entity $el
        if (-not $parsed) { continue }
        [void]$tables.Add($parsed.Table)
        foreach ($c in $parsed.Columns) { [void]$columns.Add($c) }
    }
    return [pscustomobject]@{ Tables=$tables; Columns=$columns }
}

function Read-Relationships {
    param([string]$Root,$Cust)
    $rels = New-Object System.Collections.ArrayList
    $relNodes = $null
    $relFile = Join-Path $Root 'Other\Relationships.xml'
    if (Test-Path $relFile) {
        $xml = Get-Xml $relFile
        if ($xml) { $relNodes = $xml.SelectNodes("//EntityRelationship") }
    } elseif ($Cust) {
        $relNodes = $Cust.DocumentElement.SelectNodes("EntityRelationships/EntityRelationship")
    }
    if ($relNodes) {
        foreach ($r in $relNodes) {
            $name = Get-Attr $r 'Name'
            if (-not $name) { $name = Get-ChildText $r 'EntityRelationshipName' }
            $type = Get-ChildText $r 'EntityRelationshipType'
            if ($type -eq 'ManyToMany') {
                [void]$rels.Add([pscustomobject]@{ Name=$name; Type=$type; Referencing=(Get-ChildText $r 'FirstEntityName'); Referenced=(Get-ChildText $r 'SecondEntityName'); ViaAttribute='' })
            } else {
                [void]$rels.Add([pscustomobject]@{ Name=$name; Type=$type; Referencing=(Get-ChildText $r 'ReferencingEntityName'); Referenced=(Get-ChildText $r 'ReferencedEntityName'); ViaAttribute=(Get-ChildText $r 'ReferencingAttributeName') })
            }
        }
    }
    return ,$rels
}

function Read-AppModules {
    param([string]$Root,$Cust)
    $apps = New-Object System.Collections.ArrayList
    $appNodes = New-Object System.Collections.ArrayList
    $dir = Join-Path $Root 'AppModules'
    if (Test-Path $dir) {
        foreach ($appDir in Get-ChildItem -Path $dir -Directory) {
            $appXml = Get-Xml (Join-Path $appDir.FullName 'AppModule.xml')
            if ($appXml -and $appXml.DocumentElement) { [void]$appNodes.Add($appXml.DocumentElement) }
        }
    } elseif ($Cust) {
        foreach ($n in $Cust.DocumentElement.SelectNodes("AppModules/AppModule")) { [void]$appNodes.Add($n) }
    }
    foreach ($n in $appNodes) {
        $unique = Get-ChildText $n 'UniqueName'
        if (-not $unique) { $unique = Get-Attr $n 'UniqueName' }
        $display = $unique
        $ln = $n.SelectSingleNode(".//LocalizedNames/LocalizedName")
        if ($ln) { $d = Get-Attr $ln 'description'; if ($d) { $display = $d } }
        [void]$apps.Add([pscustomobject]@{ Unique=$unique; Display=$display })
    }
    return ,$apps
}

function Read-SiteMaps {
    param([string]$Root,$Cust)
    $maps = New-Object System.Collections.ArrayList
    $sources = New-Object System.Collections.ArrayList
    $appDir = Join-Path $Root 'AppModules'
    if (Test-Path $appDir) {
        foreach ($xmlFile in Get-ChildItem -Path $appDir -Recurse -Filter *.xml) {
            $sm = Get-Xml $xmlFile.FullName
            if ($sm -and $sm.SelectNodes("//Area").Count -gt 0) { [void]$sources.Add([pscustomobject]@{ Name=$xmlFile.BaseName; Node=$sm }) }
        }
    }
    if ($sources.Count -eq 0 -and $Cust) {
        foreach ($asm in $Cust.SelectNodes("//AppModuleSiteMap")) {
            if ($asm.SelectNodes(".//Area").Count -gt 0) {
                $nm = Get-ChildText $asm 'SiteMapUniqueName'
                if (-not $nm) { $nm = 'sitemap' }
                [void]$sources.Add([pscustomobject]@{ Name=$nm; Node=$asm })
            }
        }
        if ($sources.Count -eq 0) {
            foreach ($sm in $Cust.SelectNodes("//SiteMap")) {
                if ($sm.SelectNodes(".//Area").Count -gt 0) { [void]$sources.Add([pscustomobject]@{ Name='sitemap'; Node=$sm }) }
            }
        }
    }
    foreach ($src in $sources) {
        $areas = New-Object System.Collections.ArrayList
        foreach ($area in $src.Node.SelectNodes(".//Area")) {
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
        [void]$maps.Add([pscustomobject]@{ Name=$src.Name; Areas=$areas })
    }
    return ,$maps
}

function Parse-TopicSource {
    param([string]$Name,[string[]]$Lines,[int]$LineCap)
    $displayName = $Name
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*displayName:\s*(.+)$') { $displayName = $matches[1].Trim().Trim('"').Trim("'"); break }
    }
    $triggers = New-Object System.Collections.ArrayList
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*triggerQueries:\s*$') {
            for ($j=$i+1; $j -lt $Lines.Count; $j++) {
                if ($Lines[$j] -match '^\s*-\s*(.+)$') { [void]$triggers.Add(($matches[1].Trim().Trim('"').Trim("'"))) }
                elseif ($Lines[$j] -match '^\s*$') { continue } else { break }
            }
        }
    }
    $knowledge = New-Object System.Collections.ArrayList
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '(?i)(knowledgeSources|searchEnabled|dataSource|sharePointSearch|publicWebSearch)') { [void]$knowledge.Add($Lines[$i].Trim()) }
    }
    $raw = if ($Lines.Count -gt $LineCap) { ($Lines[0..($LineCap-1)] -join "`r`n") + "`r`n... [truncated $($Lines.Count - $LineCap) lines]" } else { ($Lines -join "`r`n") }
    return [pscustomobject]@{ File=$Name; DisplayName=$displayName; Triggers=$triggers; Knowledge=$knowledge; Raw=$raw }
}

function Read-Bots {
    param([string]$Root,$Cust,[int]$LineCap)
    $bots = New-Object System.Collections.ArrayList
    foreach ($f in Get-ChildItem -Path $Root -Recurse -Include *.yaml,*.yml -ErrorAction SilentlyContinue) {
        $lines = Get-Content -Path $f.FullName -Encoding UTF8
        [void]$bots.Add((Parse-TopicSource -Name ($f.BaseName -replace '\.topic$','') -Lines $lines -LineCap $LineCap))
    }
    if ($bots.Count -eq 0 -and $Cust) {
        foreach ($bc in $Cust.SelectNodes("//botcomponent")) {
            $nm = Get-ChildText $bc 'name'
            if (-not $nm) { $nm = Get-Attr $bc 'schemaname' }
            if (-not $nm) { $nm = 'botcomponent' }
            $data = $bc.SelectSingleNode("data")
            $content = if ($data) { $data.InnerText } else { $bc.InnerText }
            if ($content -and ($content -match '(?i)(triggerQueries|kind:|beginDialog)')) {
                $lines = $content -split "`r?`n"
                [void]$bots.Add((Parse-TopicSource -Name $nm -Lines $lines -LineCap $LineCap))
            }
        }
    }
    return ,$bots
}

function Read-Inventory {
    param([string]$Root,$Sol,$Cust)
    $man = if ($Sol) { $Sol.SelectSingleNode("//SolutionManifest") } else { $null }
    $pub = if ($man) { $man.SelectSingleNode("Publisher") } else { $null }
    $inv = [ordered]@{
        UniqueName = if ($man) { Get-ChildText $man 'UniqueName' } else { '' }
        Version    = if ($man) { Get-ChildText $man 'Version' } else { '' }
        Managed    = if ($man) { Get-ChildText $man 'Managed' } else { '' }
        Publisher  = if ($pub) { Get-ChildText $pub 'UniqueName' } else { '' }
        Prefix     = if ($pub) { Get-ChildText $pub 'CustomizationPrefix' } else { '' }
    }
    $inv.GlobalChoiceCount  = if ($Cust) { $Cust.SelectNodes("//optionsets/optionset").Count } else { 0 }
    $inv.ConnectionRefCount = if ($Cust) { $Cust.SelectNodes("//connectionreferences/connectionreference").Count } else { 0 }
    $inv.EnvVariableCount   = if ($Cust) { $Cust.SelectNodes("//environmentvariabledefinitions/environmentvariabledefinition").Count } else { 0 }
    $inv.WorkflowCount      = if ($Cust) { $Cust.SelectNodes("//Workflows/Workflow").Count } else { 0 }
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

$solPath = Find-File $root @('solution.xml','Other\Solution.xml')
$custPath = Find-File $root @('customizations.xml','Other\Customizations.xml')
$sol = Get-Xml $solPath
$cust = Get-Xml $custPath

$layout = 'unknown'
if (Test-Path (Join-Path $root 'Entities')) { $layout = 'unpacked tree (pac solution unpack)' }
elseif (Test-Path (Join-Path $root 'customizations.xml')) { $layout = 'raw unzipped export' }
elseif ($cust) { $layout = 'export (customizations.xml found under Other\)' }
Write-Host "Layout detected: $layout"
Write-Host ("solution.xml: {0}" -f $(if ($solPath) { $solPath } else { 'NOT FOUND' }))
Write-Host ("customizations.xml: {0}" -f $(if ($custPath) { $custPath } else { 'NOT FOUND' }))

$tablesResult = Read-Tables -Root $root -Cust $cust
$tables  = @($tablesResult.Tables)
$columns = @($tablesResult.Columns)
$rels    = @(Read-Relationships -Root $root -Cust $cust)
$apps    = @(Read-AppModules -Root $root -Cust $cust)
$maps    = @(Read-SiteMaps -Root $root -Cust $cust)
$bots    = @(Read-Bots -Root $root -Cust $cust -LineCap $RawYamlLineCap)
$inv     = Read-Inventory -Root $root -Sol $sol -Cust $cust

Write-Host ("Parsed: {0} tables, {1} columns, {2} relationships, {3} apps, {4} sitemaps, {5} agent topics" -f $tables.Count,$columns.Count,$rels.Count,$apps.Count,$maps.Count,$bots.Count)

if (($tables.Count + $apps.Count + $bots.Count) -eq 0) {
    Write-Host ''
    Write-Host 'Nothing parsed. Top-level contents of the folder:'
    Get-ChildItem -Path $root | Select-Object Mode,Name | Format-Table -AutoSize | Out-Host
}

$tablesCsv = Join-Path $OutputFolder '01_Tables.csv'
$columnsCsv = Join-Path $OutputFolder '02_Columns.csv'
$relsCsv = Join-Path $OutputFolder '03_Relationships.csv'
$invTxt = Join-Path $OutputFolder '04_ComponentInventory.txt'
$mdaTxt = Join-Path $OutputFolder '05_MDA_Specification.txt'
$agentTxt = Join-Path $OutputFolder '06_AgentDesign.txt'

if ($tables.Count -gt 0)  { $tables  | Export-Csv -Path $tablesCsv -NoTypeInformation -Encoding UTF8 }  else { Set-Content -Path $tablesCsv -Value 'Logical,Display,Columns' -Encoding UTF8 }
if ($columns.Count -gt 0) { $columns | Export-Csv -Path $columnsCsv -NoTypeInformation -Encoding UTF8 } else { Set-Content -Path $columnsCsv -Value 'Table,Logical,Display,Type,Required,Choices' -Encoding UTF8 }
if ($rels.Count -gt 0)    { $rels    | Export-Csv -Path $relsCsv -NoTypeInformation -Encoding UTF8 }    else { Set-Content -Path $relsCsv -Value 'Name,Type,Referencing,Referenced,ViaAttribute' -Encoding UTF8 }

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
[void]$L.Add("Tables: $($tables.Count)")
[void]$L.Add("Model-driven apps: $($apps.Count)")
[void]$L.Add("Site maps: $($maps.Count)")
[void]$L.Add("Agent topics: $($bots.Count)")
[void]$L.Add("Cloud flows / workflows: $($inv.WorkflowCount)")
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
[void]$L.Add('Apps')
[void]$L.Add('----')
if ($apps.Count -eq 0) { [void]$L.Add('No model-driven apps found in this solution.') }
foreach ($a in $apps) { [void]$L.Add("- $($a.Display)  ($($a.Unique))") }
[void]$L.Add('')
[void]$L.Add('Site maps')
[void]$L.Add('---------')
if ($maps.Count -eq 0) { [void]$L.Add('No site maps found.') }
$surfaced = New-Object System.Collections.ArrayList
foreach ($m in $maps) {
    [void]$L.Add("SITE MAP: $($m.Name)")
    foreach ($area in $m.Areas) {
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
}
[void]$L.Add('Tables surfaced across all site maps')
[void]$L.Add('------------------------------------')
if ($surfaced.Count -eq 0) { [void]$L.Add('None resolved.') }
foreach ($e in $surfaced) { [void]$L.Add("- $e") }
Save-Text -Lines $L -Path $mdaTxt

$L = New-Object System.Collections.ArrayList
[void]$L.Add('AGENT DESIGN')
[void]$L.Add('============')
[void]$L.Add('')
if ($bots.Count -eq 0) { [void]$L.Add('No agent topic files found in this solution.') }
foreach ($b in $bots) {
    [void]$L.Add("TOPIC: $($b.DisplayName)")
    [void]$L.Add("Source: $($b.File)")
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
    foreach ($line in ($b.Raw -split "`r?`n")) { [void]$L.Add("  $line") }
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
