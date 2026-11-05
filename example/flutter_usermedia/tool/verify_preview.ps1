param(
    [string]$Adb = 'C:\projects\android-tools\sdk\platform-tools\adb.exe',
    [string]$Dir = 'C:\projects\zteams\dart-usermedia\example\flutter_usermedia'
)

function Grab($name) {
    & $Adb shell screencap -p /sdcard/_shot.png | Out-Null
    & $Adb pull /sdcard/_shot.png "$Dir\$name" 2>&1 | Out-Null
}

Add-Type -AssemblyName System.Drawing

# Preview region (right side of the 300dp sidebar) in device px.
$x0 = 800; $x1 = 1070; $y0 = 250; $y1 = 1200

function RegionStats($p) {
    $bmp = [System.Drawing.Bitmap]::FromFile($p)
    $nz = 0; $n = 0
    for ($x = $x0; $x -lt $x1; $x += 12) {
        for ($y = $y0; $y -lt $y1; $y += 12) {
            $c = $bmp.GetPixel($x, $y)
            if (($c.R + $c.G + $c.B) -gt 30) { $nz++ }
            $n++
        }
    }
    $bmp.Dispose()
    return @($nz, $n)
}

function DiffRegion($p1, $p2) {
    $b1 = [System.Drawing.Bitmap]::FromFile($p1)
    $b2 = [System.Drawing.Bitmap]::FromFile($p2)
    $d = 0; $n = 0
    for ($x = $x0; $x -lt $x1; $x += 10) {
        for ($y = $y0; $y -lt $y1; $y += 10) {
            $c1 = $b1.GetPixel($x, $y); $c2 = $b2.GetPixel($x, $y)
            $d += [math]::Abs($c1.R - $c2.R) + [math]::Abs($c1.G - $c2.G) + [math]::Abs($c1.B - $c2.B)
            $n++
        }
    }
    $b1.Dispose(); $b2.Dispose()
    return [math]::Round($d / $n, 2)
}

Grab 'emu_a.png'
Start-Sleep -Milliseconds 1200
Grab 'emu_b.png'

$sa = RegionStats "$Dir\emu_a.png"
"preview non-dark pixels (a): $($sa[0])/$($sa[1])"
"mean per-pixel diff a->b in preview: $(DiffRegion "$Dir\emu_a.png" "$Dir\emu_b.png")"
