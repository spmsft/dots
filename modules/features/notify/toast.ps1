# dots-managed - Windows toast/balloon notification helper invoked by
# modules/features/notify/notify.sh on WSL. Uses System.Windows.Forms'
# NotifyIcon balloon tip (built into every Windows PowerShell - no extra
# module, no AppUserModelID registration needed) rather than the raw
# Windows.UI.Notifications.ToastNotificationManager API, which throws
# unless the calling process has a properly registered AUMID. Modern
# Windows (10+) automatically renders NotifyIcon balloon tips as real
# Action Center toast notifications, so this gets the same visible
# result without the registration requirement.
#
# Known cosmetic limitation: Action Center attributes the toast's source
# to the actual calling process (powershell.exe/pwsh.exe), not $AppName.
# Overriding that reliably requires a full AUMID + registered Start Menu
# shortcut identity (or the modern packaged Toast API) - considered not
# worth the added complexity for this feature; $AppName is still shown
# as the tray icon's hover tooltip text.
#
# All free-text (title/message) is passed base64-encoded (bash side does
# NOT need to shell-escape into PowerShell source at all this way -
# avoids any quoting/injection concerns for text containing quotes,
# backticks, `$`, etc.)
param(
    [Parameter(Mandatory = $true)][string]$TitleB64,
    [string]$MessageB64 = "",
    [string]$IconPath = "",
    [int]$TimeoutMs = 5000,
    [ValidateSet("low", "normal", "critical")][string]$Urgency = "normal",
    [string]$AppName = "dots"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Decode-Base64Utf8 {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Value))
}

$title = Decode-Base64Utf8 -Value $TitleB64
$message = Decode-Base64Utf8 -Value $MessageB64

$icon = [System.Drawing.SystemIcons]::Information
if (-not [string]::IsNullOrEmpty($IconPath) -and (Test-Path -LiteralPath $IconPath)) {
    try {
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($IconPath)
    } catch {
        # Fall back to the default informational icon on any extraction failure
        # (e.g. the path isn't actually an icon-bearing file).
    }
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $icon
$notifyIcon.Text = $AppName
$notifyIcon.Visible = $true
$notifyIcon.BalloonTipTitle = $title
$notifyIcon.BalloonTipText = $message

switch ($Urgency) {
    "critical" { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error }
    "low"      { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::None }
    default    { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info }
}

$notifyIcon.ShowBalloonTip($TimeoutMs)

# NotifyIcon needs the process to stay alive for the balloon to actually
# render/persist - exiting immediately after ShowBalloonTip() can race
# the toast out of existence before Explorer picks it up.
Start-Sleep -Milliseconds ($TimeoutMs + 500)

$notifyIcon.Visible = $false
$notifyIcon.Dispose()
