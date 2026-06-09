$now = Get-Date -Format yyyy-MM-dd_HHmmss
New-Item -ItemType Directory -Path .\removed_assets -Force | Out-Null
$lutFiles = Get-ChildItem -Path .\assets\luts -Filter '*.bin' -File -ErrorAction SilentlyContinue
if ($lutFiles -and $lutFiles.Count -gt 0) {
  $lutPaths = $lutFiles | ForEach-Object { $_.FullName }
  Compress-Archive -Path $lutPaths -DestinationPath ".\removed_assets\luts_removed_$now.zip" -Force
}
$modelPath = '.\assets\models\color_transfer.tflite'
if (Test-Path $modelPath) {
  Compress-Archive -Path $modelPath -DestinationPath ".\removed_assets\color_transfer_$now.zip" -Force
}
Get-ChildItem .\removed_assets | Select-Object Name, @{Name='SizeMB';Expression={[math]::Round($_.Length/1MB,2)}} | Format-Table -AutoSize
if (Test-Path ".\removed_assets\luts_removed_$now.zip") {
  $lutFiles | Remove-Item -Force
}
if (Test-Path ".\removed_assets\color_transfer_$now.zip") {
  Remove-Item $modelPath -Force
}
Write-Output ("Post-delete: LUT count=" + (Get-ChildItem -Path .\assets\luts -Filter '*.bin' -File -ErrorAction SilentlyContinue | Measure-Object).Count)
Write-Output ("Model exists now: " + (Test-Path $modelPath))
