<#
.SYNOPSIS
Restores the %SYSTEMDRIVE%\inetpub directory and resets its default security permissions and ownership.

.DESCRIPTION
This script addresses the creation of the %SYSTEMDRIVE%\inetpub directory introduced by Windows update KB5055523 as a mitigation for CVE-2025-21204.
It facilitates the restoration of this directory and its required permissions for users who may have previously deleted it, without necessitating the enablement or disablement of IIS features.

The script performs the following actions:
1. Ensures the %SYSTEMDRIVE%\inetpub directory exists, creating it if absent.
2. Applies the standard Access Control List (ACL) permissions to the %SYSTEMDRIVE%\inetpub directory, using the settings captured after the installation of KB5055523. This action overwrites existing permissions on the directory itself.
3. Sets the owner of the %SYSTEMDRIVE%\inetpub directory to 'NT AUTHORITY\SYSTEM'.

Important Considerations:
- If the directory already contains files or subdirectories, the permission reset and ownership change will only apply directly to the %SYSTEMDRIVE%\inetpub directory itself. Inheritance will apply standard rules, but existing child item permissions are not forcefully overwritten, and ownership of child items is not changed.
- The script requires elevation (Run as Administrator) to modify system directories and permissions.

.PARAMETER NoWait
Suppresses the final "Press any key to continue..." prompt, causing the script to exit immediately upon completion without waiting for user input.

.EXAMPLE
PS C:\> .\Reset.ps1

Description:
-----------
Executes the script. It will create or verify the inetpub directory, apply the necessary permissions and ownership, display status messages, and pause for confirmation upon completion. Requires an elevated PowerShell session.

.EXAMPLE
PS C:\> .\Reset.ps1 -NoWait

Description:
-----------
Executes the script in the same manner as the first example, but the -NoWait switch prevents the script from pausing at the end. It will exit immediately after displaying the final status message. Requires an elevated PowerShell session.

.NOTES

Author: mmotti (https://github.com/mmotti)
Requires:    Windows PowerShell 5.1 or later.
Requires:    Administrator privileges.
Warning:     This script modifies file system permissions and ownership on the %SYSTEMDRIVE%\inetpub directory. Ensure you understand the changes before execution.

.LINK
GitHub Repository: https://github.com/mmotti/Reset-inetpub
KB5055523: https://support.microsoft.com/en-gb/topic/april-8-2025-kb5055523-os-build-26100-3775-277a9d11-6ebf-410c-99f7-8c61957461eb
CVE-2025-21204: https://msrc.microsoft.com/update-guide/vulnerability/CVE-2025-21204
#>
#Requires -RunAsAdministrator

param (
    [Parameter()]
    [switch] $NoWait
)

function Write-Status {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateSet("INFO", "ACTION", "OK", "FAIL", "WARN", IgnoreCase=$true)]
        [string] $Status,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [int] $Indent = 0
    )

        $okPrefix = "[OK]"
        $failPrefix = "[FAIL]"
        $warningPrefix = "[WARN]"
        $actionPrefix = "[>>]"
        $infoPrefix = "[i]"

        switch ($Status.ToUpperInvariant()) {
            "ACTION" {$prefix=$actionPrefix;$colour="Blue"}
            "OK" {$prefix=$okPrefix;$colour="Green"}
            "FAIL" {$prefix=$failPrefix;$colour="Red"}
            "WARN" {$prefix=$warningPrefix;$colour="Yellow"}
            "INFO" {$prefix=$infoPrefix; $colour="White"}
            default {$prefix=$null; $colour="White"}
        }

        if ($Indent -gt 0) {
            Write-Host ("`t" * $Indent) -NoNewline
        }

        if ($prefix) {
            Write-Host $prefix -ForegroundColor $colour -NoNewline
            $Message = " $Message"
        }

        Write-Host $Message
}

Clear-Host

# SYSTEMDRIVE:\inetpub
$targetPath = Join-Path -Path $env:SystemDrive -ChildPath "inetpub"

# Permissions as of 24/04/25
$aclImportString = @"
$(Split-Path -Path $targetPath -Leaf)
D:PAI(A;;FA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;OICIIO;GA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;;FA;;;SY)(A;OICIIO;GA;;;SY)(A;;FA;;;BA)(A;OICIIO;GA;;;BA)(A;;0x1200a9;;;BU)(A;OICIIO;GXGR;;;BU)(A;OICIIO;GA;;;CO)S:AINO_ACCESS_CONTROL
"@

$sddlComparisonString = "O:SYG:SYD:PAI(A;OICIIO;GA;;;CO)(A;OICIIO;GA;;;SY)(A;;FA;;;SY)(A;OICIIO;GA;;;BA)(A;;FA;;;BA)(A;OICIIO;GXGR;;;BU)(A;;0x1200a9;;;BU)(A;OICIIO;GA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;;FA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)"

$aclChangeRequired = $false
$aclOwnerChangeRequired = $false
$aclGroupChangeRequired = $false
$scriptErrorOccurred = $false
$desiredAccount = $null
$expectedOwnerString = "NT AUTHORITY\SYSTEM"

try {
    try {
        $desiredAccount = New-Object System.Security.Principal.NTAccount($expectedOwnerString)
    }
    catch {
        throw "Failed to create NTAccount object for owner '$expectedOwnerString'. Error: $($_.Exception.Message)"
    }

    if (-not(Test-Path -Path $targetPath -PathType Container)) {
        Write-Status -Status ACTION -Message "Creating directory '$targetPath'"
        New-Item -Path $targetPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $aclChangeRequired = $true; $aclOwnerChangeRequired = $true; $aclGroupChangeRequired = $true
        Write-Status -Status OK -Message "Directory created." -Indent 1
    } else {
        Write-Status -Status ACTION -Message "Checking permissions of '$targetPath'"
        $currentACL = $null
        try {
            $currentACL = Get-Acl -Path $targetPath -ErrorAction Stop
        }
        catch {
            Write-Status -Status WARN -Message "Unable to determine permissions for '$targetPath' due to error: $($_.Exception.Message). Assuming an update is required for all components." -Indent 1
            $aclChangeRequired = $true; $aclOwnerChangeRequired = $true; $aclGroupChangeRequired = $true
        }

        if ($currentACL) {
            if ($currentACL.Sddl -eq $sddlComparisonString) {
                Write-Status -Status OK -Message "Permissions verified." -Indent 1
            } else {
                Write-Status -Status WARN -Message "Permissions require updating (SDDL mismatch)." -Indent 1
                $aclChangeRequired = $true

                Write-Status -Status ACTION -Message "Checking the owner of '$targetPath'"

                if ($currentACL.Owner -ne $desiredAccount.Value) {
                    Write-Status -Status WARN -Message "Ownership requires updating." -Indent 1
                    $aclOwnerChangeRequired = $true
                } else {
                    Write-Status -Status OK -Message "Ownership verified." -Indent 1
                }

                Write-Status -Status ACTION -Message "Checking the primary group of '$targetPath'"

                if ($currentACL.Group -ne $desiredAccount.Value) {
                    Write-Status -Status WARN -Message "Primary group requires updating." -Indent 1
                    $aclGroupChangeRequired = $true
                } else {
                    Write-Status -Status OK -Message "Primary group verified." -Indent 1
                }
            }
        }
    }

    if (-not ($aclGroupChangeRequired -or $aclChangeRequired -or $aclOwnerChangeRequired)) {
        Write-Status -Status OK -Message "No changes are required."
        exit 0
    } else {

        Write-Status -Status ACTION -Message "Checking contents of '$targetPath' before applying changes."

        if (Get-ChildItem -Path $targetPath -ErrorAction SilentlyContinue) {
            Write-Status -Status WARN -Message "'$targetPath' is not empty!" -Indent 1
            Write-Status -Status WARN -Message "Ownership and direct permission changes (default settings) will only apply to the parent directory ($targetPath) and will not be applied recursively." -Indent 1
            Write-Status -Status WARN -Message "However, inheritable permissions from the parent will propagate to subdirectories as expected." -Indent 1
            Write-Status -Status WARN -Message "This approach helps prevent potential issues with manually applied permissions." -Indent 1
        } else {
            Write-Status -Status OK -Message "'$targetPath' exists and is empty." -Indent 1
        }

        if ($aclGroupChangeRequired) {
            Write-Status -Status ACTION -Message "Setting the primary group of '$targetPath' to '$($desiredAccount.Value)'."
            $groupACL = Get-Acl -Path $targetPath -ErrorAction Stop
            $groupACL.SetGroup($desiredAccount)
            Set-Acl -Path $targetPath -AclObject $groupACL -ErrorAction Stop
            Write-Status -Status OK -Message "Primary group successfully set." -Indent 1
        }

        if ($aclChangeRequired) {
            Write-Status -Status ACTION -Message "Importing necessary permissions"
            $aclFile = $null
            try {
                $aclFile = New-TemporaryFile -ErrorAction Stop
                Set-Content -Value $aclImportString -Path $aclFile.FullName -Encoding unicode -Force -ErrorAction Stop
                $result = icacls "$env:SystemDrive\" /restore $aclFile.FullName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "icacls /restore failed for '$targetPath'. Output: $result"
                }
                Write-Status -Status OK -Message "Permissions successfully imported." -Indent 1
            } finally {
                if ($aclFile) { $aclFile | Remove-Item -Force -ErrorAction SilentlyContinue }
            }
        }

        if ($aclOwnerChangeRequired) {
            Write-Status -Status ACTION -Message "Setting owner of '$targetPath' to '$expectedOwnerString'"
            $result = icacls $targetPath /SetOwner "SYSTEM" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "icacls /SetOwner failed for '$targetPath'. Output: $result"
            }
            Write-Status -Status OK -Message "Owner successfully set." -Indent 1
        }
    }
} catch {
    Write-Status -Status FAIL -Message "An error occurred: $($_.Exception.Message)" -Indent 1
    $scriptErrorOccurred = $true
} finally {
    Write-Host
    $statusParams = @{
        Status = if ($scriptErrorOccurred) { "FAIL" } else { "OK" }
        Message = if ($scriptErrorOccurred) { "Script execution completed with error(s)." } else { "Script execution completed successfully." }
    }
    Write-Status @statusParams

    if (-not($NoWait)) {
        if ($host.UI.RawUI -and ($host.UI.RawUI | Get-Member -Name "ReadKey" -MemberType Method)) {
            Write-Status -Status ACTION -Message "Press any key to continue..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } else {
            Read-Host "[>>] Press enter to continue..."
        }
    }
}

if ($scriptErrorOccurred) { exit 1 } else { exit 0 }