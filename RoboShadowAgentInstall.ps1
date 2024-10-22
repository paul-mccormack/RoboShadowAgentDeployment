# ********************************************
# If you are deploying via InTune we recommend using our InTune integration feature. https://portal.roboshadow.com/devices
# 
# How to use:
# 1. Replace YOUR_ORGANISATION_ID with the organisationID from the correct organisation in the Portal. https://portal.roboshadow.com/account/organisations
# Note: changing this after install is not trivial.
# 2. Set $haveSetOrgId to $True
# ********************************************

$organisationId = "YOUR ORGANISATION ID"
$haveSetOrgId = $True

$version = (Get-ItemProperty -Path "HKLM:\SOFTWARE\RoboShadowLtd\Rubicon\Agent" -Name "Version" -ErrorAction SilentlyContinue).$valueName

if ($haveSetOrgId -and (-not $version -or [int]($version -split '\.')[0] -lt 4)) {
  Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/i https://cdn.roboshadow.com/GetAgent/RoboShadowAgent-x64.msi /qb /norestart ORGANISATION_ID=$organisationId" -Wait
}