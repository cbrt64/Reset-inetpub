#Requires -RunAsAdministrator

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
        $infoPrefix = "[INFO]"

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

# Permissions as of 24/04/25
$aclImportString = @"
inetpub
D:P(A;;FA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;OICIIO;GA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;;FA;;;SY)(A;OICIIO;GA;;;SY)(A;;FA;;;BA)(A;OICIIO;GA;;;BA)(A;;0x1200a9;;;BU)(A;OICIIO;GXGR;;;BU)(A;OICIIO;GA;;;CO)
"@

# SYSTEMDRIVE:\inetpub
$targetPath = Join-Path -Path $env:SystemDrive -ChildPath "inetpub"

try {
    # Directory doesn't exist.
    if (-not(Test-Path -Path $targetPath -PathType Container)) {
        try {
            Write-Status -Status ACTION -Message "Creating directory '$targetPath'..."
            New-Item -Path $targetPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Status -Status OK -Message "Directory created."
        }
        catch {
            throw "Unable to to create directory: $targetPath"
        }
    # Directory exists and has children.
    } elseif (Get-ChildItem -Path $targetPath -ErrorAction SilentlyContinue) {
        Write-Status -Status WARN -Message "'$targetPath' is not empty!"
        Write-Status -Status WARN -Message "Ownership change to 'NT AUTHORITY\SYSTEM' (default setting) will only apply to the parent directory ($targetPath)."
        Write-Status -Status WARN -Message "This is to prevent any potential issues with permissions that have been manually applied."
        Write-Status -Status INFO -Message "Please press any key to acknowledge..."
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    # Directory exists and is empty.
    } else {
        Write-Status -Status OK -Message "'$targetPath' exists and is empty."
    }

    try {
        Write-Status -Status ACTION -Message "Importing necessary permissions..."

        # Create a temporary file for use with icacls restore.
        $aclFile = New-TemporaryFile -ErrorAction Stop
        Set-Content -Value $aclImportString -Path $aclFile -Encoding unicode -Force -ErrorAction Stop

        # icacls "C:\" /restore path\to\file.tmp
        $result = icacls "$env:SystemDrive\" /restore $aclFile.FullName 2>&1

        if ($LASTEXITCODE -ne 0) { throw $result } else {
            Write-Status -Status OK -Message "Permissions successfully imported."
        }
    } catch {
        throw "Failed to import permissions for '$targetPath'. Error $($_.Exception.Message)."
    } finally {
        # Remove the temporary file.
        $aclFile | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Write-Status -Status ACTION -Message "Setting owner of '$targetPath' to 'NT AUTHORITY\SYSTEM'..."

    try {
        # Set the owner of inetpub to 'NT AUTHORITY\SYSTEM'.
        $result = icacls $targetPath /SetOwner "SYSTEM" 2>&1

        if ($LASTEXITCODE -ne 0) { throw $result } else {
            Write-Status -Status OK -Message "Owner successfully changed."
        }
    }
    catch {
        throw "Failed to set owner for '$targetPath'. Error: $($_.Exception.Message)"
    }
} catch {
    Write-Status -Status FAIL -Message $_.Exception.Message -Indent 1
    exit 1
} finally {
    Write-Host ("-" * 25)
    Write-Status -Status OK -Message "Script execution complete."
    Write-Status -Status INFO -Message "Press any key to continue..."
    # Pause on exit.
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}