$ErrorActionPreference = "Stop"
$j = Get-Content "game\data\world_regions.json" -Raw -Encoding UTF8 | ConvertFrom-Json

$tierCount = @{}
$totalStairs = 0
$totalHalls = 0
$totalAnchors = 0
$totalNiche = 0
$totalR5 = 0
$rows = @()

foreach ($p in $j.regions.PSObject.Properties) {
    $id = $p.Name
    $v = $p.Value
    $s = $v.structure
    $lv = if ($null -ne $v.layout_version) { [int]$v.layout_version } else { 6 }

    $rooms = $v.rooms
    $floorOf = @{}
    for ($i = 0; $i -lt $rooms.Count; $i++) {
        $r = $rooms[$i].rect
        $floorOf[$i] = [double]$r[1] + [double]$r[3]
    }

    # connection meta by link index
    $meta = @{}
    foreach ($c in $s.connections) { $meta[[int]$c.link] = $c }

    $stairs = 0
    for ($i = 0; $i -lt $v.links.Count; $i++) {
        $a = $v.links[$i][0]; $b = $v.links[$i][1]
        $ay = $floorOf[[int]$a]; $by = $floorOf[[int]$b]
        if ([math]::Abs($ay - $by) -lt 1) { continue }
        $tier = $null
        if ($meta.ContainsKey($i)) { $tier = [string]$meta[$i].tier }
        if (-not $tier) { $tier = "?" }
        if ($tierCount.ContainsKey($tier)) { $tierCount[$tier]++ } else { $tierCount[$tier] = 1 }

        if ($lv -eq 7) {
            # new generator: landings from data
            $lm = 0
            if ($meta.ContainsKey($i)) { $lm = [int]$meta[$i].landings }
            $stairs += $lm
        } else {
            $span = [math]::Abs($by - $ay)
            if ($tier -eq "R1" -or $tier -eq "R2") {
                $rise = if ($tier -eq "R1") { 48.0 } else { 128.0 }
                $n = [math]::Ceiling($span / $rise) - 1
                if ($n -lt 0) { $n = 0 }
                $stairs += $n
            } elseif ($tier -eq "R3") {
                $stairs += 2
            } else {
                $stairs += 1
            }
        }
    }

    $halls = 0
    foreach ($h in $s.pogo_halls) {
        if ($lv -eq 7) { $halls += 0 } else {
            $halls += 3            # floor + 1-2 mid
            $halls += 6            # wall stairs
        }
    }
    if ($rooms.Count -gt 0 -and $lv -ne 7) {
        # M01 special branch adds 7 + 2 platforms
        if ($id -eq "M01") { $halls += 9 }
    }

    $misc = 0
    if ($lv -ne 7) {
        foreach ($hz in $s.hazards) { if ([int]$hz.hall -lt 0) { $misc += 1 } }
        if ($s.tiers -contains "R5") { $misc += 4 }
        $misc += [int]$s.niches * 2
    } else {
        foreach ($hz in $s.hazards) { if ([int]$hz.hall -lt 0) { $misc += 1 } }
        $misc += [int]$s.niches * 2
    }

    $anchors = 0
    if ($lv -ne 7) {
        foreach ($it in $v.interactions) { if ($it.id -ne "mythic_1") { $anchors += 1 } }
    }

    $total = $stairs + $halls + $misc + $anchors
    $totalStairs += $stairs; $totalHalls += $halls
    $totalAnchors += $anchors; $totalNiche += $misc; $totalR5 += 0

    $rows += [pscustomobject]@{
        id = $id; lv = $lv; rooms = $rooms.Count; links = $v.links.Count
        stairs = $stairs; halls = $halls; misc = $misc; anchors = $anchors; total = $total
    }
}

Write-Output "=== tier distribution ==="
foreach ($k in $tierCount.Keys | Sort-Object) { Write-Output ("  {0,-4} {1}" -f $k, $tierCount[$k]) }

Write-Output ""
Write-Output "id    lv rooms links stairs halls misc anchors total"
foreach ($r in $rows) {
    Write-Output ("{0,-5} {1}  {2,3}  {3,4}  {4,5} {5,4} {6,4} {7,6} {8,6}" -f $r.id,$r.lv,$r.rooms,$r.links,$r.stairs,$r.halls,$r.misc,$r.anchors,$r.total)
}

$sum = ($rows | Measure-Object -Property total -Sum).Sum
$sumS = ($rows | Measure-Object -Property stairs -Sum).Sum
$sumH = ($rows | Measure-Object -Property halls -Sum).Sum
$sumA = ($rows | Measure-Object -Property anchors -Sum).Sum
$sumM = ($rows | Measure-Object -Property misc -Sum).Sum

Write-Output ""
Write-Output ("TOTAL platforms = {0}   (stairs {1} / halls {2} / misc {3} / anchors {4})" -f $sum,$sumS,$sumH,$sumM,$sumA)
Write-Output ("avg per region  = {0:N1}" -f ($sum / $rows.Count))
