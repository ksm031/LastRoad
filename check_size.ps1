[Reflection.Assembly]::LoadWithPartialName('System.Drawing') | Out-Null
$i = [System.Drawing.Image]::FromFile('d:\Git\LastRoad\Asset\Image\Character\watcher_idle_01.png')
Write-Output ("Idle size: " + $i.Width + "x" + $i.Height)
$d = [System.Drawing.Image]::FromFile('d:\Git\LastRoad\Asset\Image\Character\watcher_down_01.png')
Write-Output ("Down size: " + $d.Width + "x" + $d.Height)
