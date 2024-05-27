# Usage: scoop cleanup <app> [options]
# Summary: Cleanup apps by removing old versions
# Help: 'scoop cleanup' cleans Scoop apps by removing old versions.
# 'scoop cleanup <app>' cleans up the old versions of that app if said versions exist.
#
# You can use '*' in place of <app> or `-a`/`--all` switch to cleanup all apps.
#
# Options:
#   -a, --all          Cleanup all apps (alternative to '*')
#   -g, --global       Cleanup a globally installed app
#   -k, --cache        Remove outdated download cache

. "$PSScriptRoot\..\lib\getopt.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1" # 'Select-CurrentVersion' (indirectly)
. "$PSScriptRoot\..\lib\versions.ps1" # 'Select-CurrentVersion'
. "$PSScriptRoot\..\lib\install.ps1" # persist related

$opt, $apps, $err = getopt $args 'agk' 'all', 'global', 'cache'
if ($err) { "scoop cleanup: $err"; exit 1 }
$global = $opt.g -or $opt.global
$cache = $opt.k -or $opt.cache
$all = $opt.a -or $opt.all

if (!$apps -and !$all) { 'ERROR: <app> missing'; my_usage; exit 1 }

if ($global -and !(is_admin)) {
    'ERROR: you need admin rights to cleanup global apps'; exit 1
}

Function rm_cleanup($path) {
    $size = (Get-ChildItem -Recurse -File $path | Measure-Object -Property Length -Sum).sum
    Remove-Item -Recurse -ErrorAction Continue -Force $path @args
    if ($?) {
        return $size
    } else {
      return 0
    }
}

function cleanup($app, $global, $verbose, $cache) {
    $totalLength = 0

    $current_version = Select-CurrentVersion -AppName $app -Global:$global
    if ($cache) {
        $totalLength += rm_cleanup "$cachedir\$app#*" -Exclude "$app#$current_version#*"
    }
    $appDir = appdir $app $global
    $versions = Get-ChildItem $appDir -Name
    $versions = $versions | Where-Object { $current_version -ne $_ -and $_ -ne 'current' }
    if (!$versions) {
        if ($verbose) { success "$app is already clean" }
        return
    }

    Write-Host -f yellow "Removing $app`:" -NoNewline
    $versions | ForEach-Object {
        $version = $_
        Write-Host " $version" -NoNewline
        $dir = versiondir $app $version $global
        # unlink all potential old link before doing recursive Remove-Item
        unlink_persist_data (installed_manifest $app $version $global) $dir
        $totalLength += rm_cleanup $dir
    }
    $leftVersions = Get-ChildItem $appDir
    if ($leftVersions.Length -eq 1 -and $leftVersions.Name -eq 'current' -and $leftVersions.LinkType) {
        attrib $leftVersions.FullName -R /L
        $totalLength += rm_cleanup $leftVersions.FullName 
        $leftVersions = $null
    }
    if (!$leftVersions) {
        $totalLength += rm_cleanup $appDir 
    }
    Write-Host ''
    return $totalLength
}

if ($apps -or $all) {
    if ($apps -eq '*' -or $all) {
        $verbose = $false
        $apps = applist (installed_apps $false) $false
        if ($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        $verbose = $true
        $apps = Confirm-InstallationStatus $apps -Global:$global
    }

    # $apps is now a list of ($app, $global) tuples
    $totalLength = 0
    $apps | ForEach-Object {
        $totalLength += cleanup @_ $verbose $cache
    }

    if ($cache) {
        $totalLength += rm_cleanup "$cachedir\*.download" -ErrorAction Ignore
    }

    if (!$verbose) {
        Write-Host "Deleted: $(filesize $totalLength)" -ForegroundColor Yellow
        success 'Everything is shiny now!'
    }
}

exit 0
