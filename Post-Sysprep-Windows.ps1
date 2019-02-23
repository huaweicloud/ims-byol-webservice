# Post-Sysprep-Windows.ps1
# run server configuration with cloudbase-init localscript
$log="C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\post-sysprep-ps.log"
# Get-Content $log -wait

function get-metadata {

    $metadata =$null
    $webclient = new-object system.net.webclient;
    $url = 'http://169.254.169.254/openstack/latest/meta_data.json'

    do {
        "read meta data from : $url" | Write-verbose
        try {
            $metadata =  $webclient.DownloadString($url) 
        } catch {
            'ERROR: get-metadata failed - do a retry '| Out-File -FilePath $log -Append
        }
        if (!$metadata) {sleep 5}
    }
    until ($metadata -match 'name')

    $metadataHashtable = Invoke-Expression $metadata.replace('[','@(').replace(']',')').replace('{','@{').replace(', ',';').replace(': ','=')
    return $metadataHashtable 
}

$meta = get-metadata
$meta | Out-File -FilePath $log -Append

if ($meta.meta.byol -match 'true') {
    'skip Windows activation - byol option found' | Out-File -FilePath $log -Append
} else {
    'start Windows activation' | Out-File -FilePath $log -Append
    'start Windows activation' | Write-Host
    cscript c:\windows\system32\slmgr.vbs /skms 100.125.XX.XX | Out-File -FilePath $log -Append
    cscript c:\windows\system32\slmgr.vbs /ato | Out-File -FilePath $log -Append
    'finished Windows activation' | Out-File -FilePath $log -Append

}

<# if ($meta.availability_zone -match 'ap-sg') {
    'change time zone for SGP' | Out-File  -FilePath $log -Append
    'change time zone for SGP' | Write-Host
    C:\scripts\packages\Timezone_Config\Timezone_Config_V1.1.ps1 'XXXXXXXX_Standard_Time'
}

'enable Windows Updates' | Out-File -FilePath $log -Append
'enable Windows Updates' | Write-Host
New-ItemProperty -Path "hklm:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -name "AUOptions" -value 4 -PropertyType DWord  -Force -ErrorAction SilentlyContinue | Out-File -FilePath $log -Append
set-ItemProperty -path "hklm:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -name "AUOptions" -value 4 -Force -ErrorAction SilentlyContinue | Out-File -FilePath $log -Append

'reset wsus client id' | Out-File -FilePath $log -Append

'stop and disable Windows Update service' | Out-File -FilePath $log -Append
Stop-Service -name wuauserv | Out-File -FilePath $log -Append
Set-Service -name wuauserv -StartupType Disabled | Out-File -FilePath $log -Append
Stop-Service -name bits| Out-File -FilePath $log -Append
Set-Service -name bits -StartupType Disabled | Out-File -FilePath $log -Append

'delete Software Distribution folder' | Out-File -FilePath $log -Append
cmd /c rd /s /q C:\Windows\SoftwareDistribution | Out-File -FilePath $log -Append

'clear SusClientID' | Out-File -FilePath $log -Append
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'SusClientId' -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'SusClientIdValidation' -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'AccountDomainSid' -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'PingID' -Force -ErrorAction SilentlyContinue

'enable and start Windows Update service' | Out-File -FilePath $log -Append
Set-Service -name wuauserv -StartupType Automatic | Out-File -FilePath $log -Append
Start-Service -name wuauserv | Out-File -FilePath $log -Append
Set-Service -name bits -StartupType Automatic | Out-File -FilePath $log -Append
Start-Service -name bits | Out-File -FilePath $log -Append

# Source: http://technet.microsoft.com/en-us/library/cc708617(v=ws.10).aspx
# WSUS uses a cookie on client computers to store various types of information, including computer group membership when client-side targeting is used.
# By default this cookie expires an hour after WSUS creates it.
# If you are using client-side targeting and change group membership, use this option in combination with detectnow to expire the cookie,
# initiate detection, and have WSUS update computer group membership.
# !!! Note that when combining parameters, you can use them only in the order specified as follows:
# wuauclt.exe /resetauthorization /detectnow
'wuauclt /resetauthorization /detectnow' | Out-File -FilePath $log -Append
wuauclt /resetauthorization /detectnow | Out-File -FilePath $log -Append

'reset wsus client id finished' | Out-File -FilePath $log -Append

'delete scripts folder' | Out-File -FilePath $log -Append
'delete scripts folder' | Write-Host
cmd /c rd /s /q C:\scripts | Out-File -FilePath $log -Append

# set driver mode from tcc to wddm
<# moved to unattent.xml
if (Test-Path "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe") {
    & "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" | Out-File -FilePath $log -Append
    & "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" -dm 0| Out-File -FilePath $log -Append
    & "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"| Out-File -FilePath $log -Append
    exit 1001 # - reboot and don’t run the plugin again on next boot
    # exit 1002 # - don’t reboot now and run the plugin again on next boot
    # exit 1003 # - reboot and run the plugin again on next boot
}
#>

"{0:yyyy-MM-dd HH:mm:ss} " -f $(Get-Date ) | Out-File -FilePath $log -Append
#>
exit 0
