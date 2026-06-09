$branch = (git rev-parse --abbrev-ref HEAD).Trim()
Write-Output "Current branch: $branch"
git rm --ignore-unmatch .\assets\luts\*.bin .\assets\models\color_transfer.tflite
try {
    git commit -m 'chore(assets): archive and remove LUT files and color_transfer model to reduce repo size'
} catch {
    Write-Output 'No changes to commit'
}
git push origin $branch
