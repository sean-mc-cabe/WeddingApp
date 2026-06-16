#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$UnpackedFolder,

    [Parameter(Mandatory=$true)]
    [string]$OutputFolder,

    [int]$RawYamlLineCap = 400
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
        Logical=$logical
        Display=$display
        Element=$EntityEl
        Columns=$cols
    }
}

function Get-EntityElements {
    param([string]$Root,$Cust)
    $els = New-Object System.Collections.ArrayList
    $entitiesDir = Join-Path $Root 'Entities'
    if (Test-Path $entitiesDir) {
        foreach ($dir in Get-ChildItem -Path $entitiesDir -Directory) {
            $xml = Get-Xml (Join-Path $dir.FullName 'Entity.xml')
            if ($xml -and $xml.DocumentElement) { [void]$els.Add($xml.DocumentElement) }
        }
    } elseif ($Cust) {
        foreach ($e in $Cust.DocumentElement.SelectNodes("Entities/Entity")) { [void]$els.Add($e) }
    }
    return ,$els
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
        if (-not $unique) { $unique = Get-Attr $n 'Name' }
        $display = Get-ChildText $n 'Name'
        $ln = $n.SelectSingleNode(".//LocalizedNames/LocalizedName")
        if ($ln) { $d = Get-Attr $ln 'description'; if ($d) { $display = $d } }
        if (-not $display) { $display = $unique }
        [void]$apps.Add([pscustomobject]@{ Unique=$unique; Display=$display })
    }
    return ,$apps
}

function Parse-SiteMapNode {
    param($Container,[string]$Name)
    $areas = New-Object System.Collections.ArrayList
    foreach ($area in $Container.SelectNodes(".//Area")) {
        $areaTitle = Get-Attr $area 'Title'
        if (-not $areaTitle) { $t = $area.SelectSingleNode("Titles/Title"); if ($t) { $areaTitle = Get-Attr $t 'Title' } }
        if (-not $areaTitle) { $areaTitle = Get-Attr $area 'Id' }
        $groups = New-Object System.Collections.ArrayList
        foreach ($grp in $area.SelectNodes("Group")) {
            $grpTitle = Get-Attr $grp 'Title'
            if (-not $grpTitle) { $t = $grp.SelectSingleNode("Titles/Title"); if ($t) { $grpTitle = Get-Attr $t 'Title' } }
            if (-not $grpTitle) { $grpTitle = Get-Attr $grp 'Id' }
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
    return [pscustomobject]@{ Name=$Name; Areas=$areas }
}

function Read-SiteMaps {
    param([string]$Root,$Cust)
    $maps = New-Object System.Collections.ArrayList
    $appDir = Join-Path $Root 'AppModules'
    if (Test-Path $appDir) {
        foreach ($xmlFile in Get-ChildItem -Path $appDir -Recurse -Filter *.xml) {
            $sm = Get-Xml $xmlFile.FullName
            if ($sm -and $sm.SelectNodes("//Area").Count -gt 0) { [void]$maps.Add((Parse-SiteMapNode -Container $sm -Name $xmlFile.BaseName)) }
        }
    }
    if ($maps.Count -eq 0 -and $Cust) {
        foreach ($asm in $Cust.DocumentElement.SelectNodes("AppModuleSiteMaps/AppModuleSiteMap")) {
            if ($asm.SelectNodes(".//Area").Count -gt 0) {
                $nm = Get-ChildText $asm 'SiteMapUniqueName'
                if (-not $nm) { $nm = Get-Attr $asm 'SiteMapUniqueName' }
                if (-not $nm) { $nm = 'sitemap' }
                [void]$maps.Add((Parse-SiteMapNode -Container $asm -Name $nm))
            }
        }
    }
    if ($maps.Count -eq 0 -and $Cust) {
        $i = 0
        foreach ($sm in $Cust.DocumentElement.SelectNodes("SiteMaps/SiteMap")) {
            if ($sm.SelectNodes(".//Area").Count -gt 0) { $i++; [void]$maps.Add((Parse-SiteMapNode -Container $sm -Name ("sitemap_$i"))) }
        }
    }
    return ,$maps
}

function Read-FormsAndViews {
    param($EntityResults)
    $forms = New-Object System.Collections.ArrayList
    $views = New-Object System.Collections.ArrayList
    $formTypeMap = @{ '2'='Main'; '5'='Mobile'; '6'='QuickView'; '7'='QuickCreate'; '8'='Dialog'; '9'='AppointmentBook'; '11'='Card'; '12'='MainInteractive' }
    foreach ($er in $EntityResults) {
        $entityEl = $er.Element
        $table = $er.Logical
        $formContainer = $entityEl.SelectSingleNode("FormXml/forms")
        if ($formContainer) {
            foreach ($systemform in $formContainer.SelectNodes("systemform")) {
                $formName = Get-ChildText $systemform "LocalizedNames/LocalizedName"
                if (-not $formName) { $ln = $systemform.SelectSingleNode("LocalizedNames/LocalizedName"); if ($ln) { $formName = Get-Attr $ln 'description' } }
                if (-not $formName) { $formName = '(unnamed)' }
                $typeCodeAttr = Get-Attr ($formContainer) 'type'
                $formNode = $systemform.SelectSingleNode("form")
                $typeCode = if ($formNode) { Get-Attr $formNode 'type' } else { $null }
                $formType = if ($typeCode -and $formTypeMap.ContainsKey($typeCode)) { $formTypeMap[$typeCode] } elseif ($typeCode) { "type$typeCode" } else { '' }
                $anyField = $false
                foreach ($tab in $systemform.SelectNodes(".//tab")) {
                    $tabName = Get-Attr $tab 'name'
                    if (-not $tabName) { $t = $tab.SelectSingleNode("labels/label"); if ($t) { $tabName = Get-Attr $t 'description' } }
                    foreach ($section in $tab.SelectNodes(".//section")) {
                        $sectionName = Get-Attr $section 'name'
                        if (-not $sectionName) { $s = $section.SelectSingleNode("labels/label"); if ($s) { $sectionName = Get-Attr $s 'description' } }
                        foreach ($control in $section.SelectNodes(".//control")) {
                            $field = Get-Attr $control 'datafieldname'
                            if (-not $field) { continue }
                            $anyField = $true
                            [void]$forms.Add([pscustomobject]@{ Table=$table; Form=$formName; Type=$formType; Tab=$tabName; Section=$sectionName; Field=$field })
                        }
                    }
                }
                if (-not $anyField) {
                    [void]$forms.Add([pscustomobject]@{ Table=$table; Form=$formName; Type=$formType; Tab=''; Section=''; Field='' })
                }
            }
        }
        $sqContainer = $entityEl.SelectSingleNode("SavedQueries/savedqueries")
        if ($sqContainer) {
            foreach ($sq in $sqContainer.SelectNodes("savedquery")) {
                $viewName = ''
                $ln = $sq.SelectSingleNode("LocalizedNames/LocalizedName")
                if ($ln) { $viewName = Get-Attr $ln 'description' }
                if (-not $viewName) { $viewName = Get-ChildText $sq 'displayname' }
                if (-not $viewName) { $viewName = '(unnamed)' }
                $isDefault = Get-ChildText $sq 'isdefault'
                $layoutCols = New-Object System.Collections.ArrayList
                $layout = $sq.SelectSingleNode("layoutxml")
                if ($layout) {
                    foreach ($cell in $layout.SelectNodes(".//cell")) {
                        $nm = Get-Attr $cell 'name'
                        if ($nm) { [void]$layoutCols.Add($nm) }
                    }
                }
                $sortText = ''
                $filterText = ''
                $fetch = $sq.SelectSingleNode("fetchxml")
                if ($fetch) {
                    $fx = $null
                    try { $fx = [xml]$fetch.InnerText } catch { $fx = $null }
                    if ($fx) {
                        $orders = New-Object System.Collections.ArrayList
                        foreach ($o in $fx.SelectNodes("//order")) {
                            $oa = Get-Attr $o 'attribute'
                            $desc = Get-Attr $o 'descending'
                            $dir = if ($desc -eq 'true') { 'desc' } else { 'asc' }
                            if ($oa) { [void]$orders.Add("$oa $dir") }
                        }
                        $sortText = ($orders -join '; ')
                        $conds = New-Object System.Collections.ArrayList
                        foreach ($c in $fx.SelectNodes("//condition")) {
                            $ca = Get-Attr $c 'attribute'
                            $cop = Get-Attr $c 'operator'
                            $cv = Get-Attr $c 'value'
                            $seg = "$ca $cop"
                            if ($cv) { $seg = "$seg $cv" }
                            [void]$conds.Add($seg.Trim())
                        }
                        $filterText = ($conds -join ' AND ')
                    }
                }
                [void]$views.Add([pscustomobject]@{
                    Table=$table; View=$viewName; IsDefault=$isDefault
                    Columns=($layoutCols -join ', '); Sort=$sortText; Filter=$filterText
                })
            }
        }
    }
    return [pscustomobject]@{ Forms=$forms; Views=$views }
}

function Parse-TopicYaml {
    param([string]$Name,[string]$ComponentType,[string[]]$Lines,[int]$LineCap)
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
        if ($Lines[$i] -match '(?i)(knowledgeSources|searchEnabled|dataSource|sharePointSearch|publicWebSearch|connectionReference|environmentVariable)') { [void]$knowledge.Add($Lines[$i].Trim()) }
    }
    $raw = if ($Lines.Count -gt $LineCap) { ($Lines[0..($LineCap-1)] -join "`r`n") + "`r`n... [truncated $($Lines.Count - $LineCap) lines]" } else { ($Lines -join "`r`n") }
    return [pscustomobject]@{ Name=$Name; ComponentType=$ComponentType; DisplayName=$displayName; Triggers=$triggers; Knowledge=$knowledge; Raw=$raw }
}

function Read-Bots {
    param([string]$Root,$Cust,[int]$LineCap)
    $bots = New-Object System.Collections.ArrayList
    $bcDir = Join-Path $Root 'botcomponents'
    if (Test-Path $bcDir) {
        foreach ($compDir in Get-ChildItem -Path $bcDir -Directory) {
            $dataFile = Join-Path $compDir.FullName 'data'
            $metaFile = Join-Path $compDir.FullName 'botcomponent.xml'
            if (-not (Test-Path $dataFile)) { continue }
            $compType = ''
            $meta = Get-Xml $metaFile
            if ($meta) {
                $ct = $meta.SelectSingleNode("//componenttype")
                if ($ct) { $compType = $ct.InnerText }
                if (-not $compType) { $ct2 = $meta.SelectSingleNode("//ComponentType"); if ($ct2) { $compType = $ct2.InnerText } }
            }
            $namePart = $compDir.Name
            $shortName = $namePart -replace '^.*\.topic\.','' -replace '^.*\.gpt\.',''
            $lines = Get-Content -Path $dataFile -Encoding UTF8
            [void]$bots.Add((Parse-TopicYaml -Name $shortName -ComponentType $compType -Lines $lines -LineCap $LineCap))
        }
    }
    if ($bots.Count -eq 0) {
        foreach ($f in Get-ChildItem -Path $Root -Recurse -Include *.yaml,*.yml -ErrorAction SilentlyContinue) {
            $lines = Get-Content -Path $f.FullName -Encoding UTF8
            [void]$bots.Add((Parse-TopicYaml -Name ($f.BaseName -replace '\.topic$','') -ComponentType '' -Lines $lines -LineCap $LineCap))
        }
    }
    return ,$bots
}

function Read-BotConfig {
    param([string]$Root)
    $info = [ordered]@{ Name=''; Instructions=''; ConfigFile='' }
    $botsDir = Join-Path $Root 'bots'
    if (-not (Test-Path $botsDir)) { return $info }
    foreach ($botDir in Get-ChildItem -Path $botsDir -Directory) {
        $info.Name = $botDir.Name
        $botXml = Get-Xml (Join-Path $botDir.FullName 'bot.xml')
        if ($botXml) {
            $inst = $botXml.SelectSingleNode("//instructions")
            if ($inst) { $info.Instructions = $inst.InnerText }
        }
        $info.ConfigFile = (Join-Path $botDir.FullName 'configuration.json')
        break
    }
    return $info
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

$entityEls = @(Get-EntityElements -Root $root -Cust $cust)
$entityResults = New-Object System.Collections.ArrayList
$tables = New-Object System.Collections.ArrayList
$columns = New-Object System.Collections.ArrayList
foreach ($el in $entityEls) {
    $parsed = Parse-Entity $el
    if (-not $parsed) { continue }
    [void]$entityResults.Add($parsed)
    [void]$tables.Add([pscustomobject]@{ Logical=$parsed.Logical; Display=$parsed.Display; Columns=$parsed.Columns.Count })
    foreach ($c in $parsed.Columns) { [void]$columns.Add($c) }
}

$rels = @(Read-Relationships -Root $root -Cust $cust)
$apps = @(Read-AppModules -Root $root -Cust $cust)
$maps = @(Read-SiteMaps -Root $root -Cust $cust)
$fv   = Read-FormsAndViews -EntityResults $entityResults
$forms = @($fv.Forms)
$views = @($fv.Views)
$bots = @(Read-Bots -Root $root -Cust $cust -LineCap $RawYamlLineCap)
$botCfg = Read-BotConfig -Root $root
$inv = Read-Inventory -Root $root -Sol $sol -Cust $cust

Write-Host ("Parsed: {0} tables, {1} columns, {2} relationships, {3} forms rows, {4} views, {5} apps, {6} sitemaps, {7} agent topics" -f $tables.Count,$columns.Count,$rels.Count,$forms.Count,$views.Count,$apps.Count,$maps.Count,$bots.Count)

$tablesCsv  = Join-Path $OutputFolder '01_Tables.csv'
$columnsCsv = Join-Path $OutputFolder '02_Columns.csv'
$relsCsv    = Join-Path $OutputFolder '03_Relationships.csv'
$invTxt     = Join-Path $OutputFolder '04_ComponentInventory.txt'
$mdaTxt     = Join-Path $OutputFolder '05_MDA_Specification.txt'
$agentTxt   = Join-Path $OutputFolder '06_AgentDesign.txt'
$formsCsv   = Join-Path $OutputFolder '07_Forms.csv'
$viewsCsv   = Join-Path $OutputFolder '08_Views.csv'

if ($tables.Count -gt 0)  { $tables  | Export-Csv -Path $tablesCsv -NoTypeInformation -Encoding UTF8 }  else { Set-Content -Path $tablesCsv -Value 'Logical,Display,Columns' -Encoding UTF8 }
if ($columns.Count -gt 0) { $columns | Export-Csv -Path $columnsCsv -NoTypeInformation -Encoding UTF8 } else { Set-Content -Path $columnsCsv -Value 'Table,Logical,Display,Type,Required,Choices' -Encoding UTF8 }
if ($rels.Count -gt 0)    { $rels    | Export-Csv -Path $relsCsv -NoTypeInformation -Encoding UTF8 }    else { Set-Content -Path $relsCsv -Value 'Name,Type,Referencing,Referenced,ViaAttribute' -Encoding UTF8 }
if ($forms.Count -gt 0)   { $forms   | Export-Csv -Path $formsCsv -NoTypeInformation -Encoding UTF8 }   else { Set-Content -Path $formsCsv -Value 'Table,Form,Type,Tab,Section,Field' -Encoding UTF8 }
if ($views.Count -gt 0)   { $views   | Export-Csv -Path $viewsCsv -NoTypeInformation -Encoding UTF8 }   else { Set-Content -Path $viewsCsv -Value 'Table,View,IsDefault,Columns,Sort,Filter' -Encoding UTF8 }

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
[void]$L.Add("Forms (rows): $($forms.Count)")
[void]$L.Add("Views: $($views.Count)")
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
if ($botCfg.Name) { [void]$L.Add("Bot: $($botCfg.Name)") }
if ($bots.Count -eq 0) { [void]$L.Add('No topics found.') }
foreach ($b in $bots) { [void]$L.Add("- $($b.DisplayName)  [$($b.ComponentType)]") }
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
[void]$L.Add('')
[void]$L.Add('Views by table (per-location filters live here)')
[void]$L.Add('-----------------------------------------------')
if ($views.Count -eq 0) { [void]$L.Add('No views found.') }
$viewsByTable = $views | Group-Object Table
foreach ($g in $viewsByTable) {
    [void]$L.Add("TABLE: $($g.Name)")
    foreach ($v in $g.Group) {
        $def = if ($v.IsDefault -eq '1') { ' [default]' } else { '' }
        [void]$L.Add("  - $($v.View)$def")
        if ($v.Filter) { [void]$L.Add("      filter: $($v.Filter)") }
        if ($v.Sort) { [void]$L.Add("      sort: $($v.Sort)") }
        if ($v.Columns) { [void]$L.Add("      columns: $($v.Columns)") }
    }
    [void]$L.Add('')
}
Save-Text -Lines $L -Path $mdaTxt

$L = New-Object System.Collections.ArrayList
[void]$L.Add('AGENT DESIGN')
[void]$L.Add('============')
[void]$L.Add('')
if ($botCfg.Name) { [void]$L.Add("Bot: $($botCfg.Name)") }
if ($botCfg.Instructions) {
    [void]$L.Add('')
    [void]$L.Add('System instructions:')
    foreach ($line in ($botCfg.Instructions -split "`r?`n")) { [void]$L.Add("  $line") }
}
[void]$L.Add('')
if ($bots.Count -eq 0) { [void]$L.Add('No agent topics found in this solution.') }
foreach ($b in $bots) {
    [void]$L.Add("TOPIC: $($b.DisplayName)")
    if ($b.ComponentType) { [void]$L.Add("Component type: $($b.ComponentType)") }
    [void]$L.Add('')
    [void]$L.Add('  Trigger phrases:')
    if ($b.Triggers.Count -eq 0) { [void]$L.Add('  None detected.') }
    foreach ($t in $b.Triggers) { [void]$L.Add("  - $t") }
    if ($b.Knowledge.Count -gt 0) {
        [void]$L.Add('')
        [void]$L.Add('  Knowledge / search / binding references:')
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
Write-Host "  $formsCsv"
Write-Host "  $viewsCsv"
Write-Host "  $invTxt"
Write-Host "  $mdaTxt"
Write-Host "  $agentTxt"
