$ErrorActionPreference = 'Stop'

$pubspecPath = Join-Path $PSScriptRoot 'pubspec.yaml'
$installerPath = Join-Path $PSScriptRoot 'build.iss'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$simplifiedChinese = [System.Text.Encoding]::GetEncoding(936)

try {
    $pubspec = [System.IO.File]::ReadAllText($pubspecPath, $utf8NoBom)
    $installer = [System.IO.File]::ReadAllText($installerPath, $simplifiedChinese)

    $pubspecPattern = '(?m)^version: ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)(?=\r?$)'
    $installerPattern = '(?m)^#define MyAppVersion "([0-9]+\.[0-9]+\.[0-9]+)"(?=\r?$)'
    $pubspecRegex = [System.Text.RegularExpressions.Regex]::new($pubspecPattern)
    $installerRegex = [System.Text.RegularExpressions.Regex]::new($installerPattern)
    $pubspecMatch = $pubspecRegex.Match($pubspec)
    $installerMatch = $installerRegex.Match($installer)

    if (-not $pubspecMatch.Success -or $pubspecRegex.Matches($pubspec).Count -ne 1) {
        throw 'Expected exactly one version entry in pubspec.yaml.'
    }
    if (-not $installerMatch.Success -or $installerRegex.Matches($installer).Count -ne 1) {
        throw 'Expected exactly one MyAppVersion definition in build.iss.'
    }

    $oldCoreVersion = '{0}.{1}.{2}' -f `
        $pubspecMatch.Groups[1].Value,
        $pubspecMatch.Groups[2].Value,
        $pubspecMatch.Groups[3].Value
    if ($installerMatch.Groups[1].Value -ne $oldCoreVersion) {
        throw "Version mismatch: pubspec.yaml is $oldCoreVersion, build.iss is $($installerMatch.Groups[1].Value)."
    }

    $major = [int]::Parse($pubspecMatch.Groups[1].Value)
    $minor = [int]::Parse($pubspecMatch.Groups[2].Value)
    $patch = [int]::Parse($pubspecMatch.Groups[3].Value) + 1
    $build = [long]::Parse($pubspecMatch.Groups[4].Value) + 1
    $newCoreVersion = "$major.$minor.$patch"
    $newPubspecVersion = "$newCoreVersion+$build"

    $pubspec = $pubspecRegex.Replace($pubspec, "version: $newPubspecVersion", 1)
    $installer = $installerRegex.Replace(
        $installer,
        "#define MyAppVersion `"$newCoreVersion`"",
        1
    )

    [System.IO.File]::WriteAllText($pubspecPath, $pubspec, $utf8NoBom)
    [System.IO.File]::WriteAllText($installerPath, $installer, $simplifiedChinese)
    Write-Output "Build version: $oldCoreVersion -> $newCoreVersion+$build"
}
catch {
    [Console]::Error.WriteLine("Version update failed: $_")
    exit 1
}
