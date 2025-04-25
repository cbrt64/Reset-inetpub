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

# SYSTEMDRIVE:\inetpub
$targetPath = Join-Path -Path $env:SystemDrive -ChildPath "inetpub"

# Permissions as of 24/04/25
$aclImportString = @"
$(Split-Path -Path $targetPath -Leaf)
D:PAI(A;;FA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;OICIIO;GA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;;FA;;;SY)(A;OICIIO;GA;;;SY)(A;;FA;;;BA)(A;OICIIO;GA;;;BA)(A;;0x1200a9;;;BU)(A;OICIIO;GXGR;;;BU)(A;OICIIO;GA;;;CO)S:AINO_ACCESS_CONTROL
"@

# Comparison string for icacls (Get-Acl Sddl is not reliable for this).
$aclComparisonString = @"
C:\inetpub NT SERVICE\TrustedInstaller:(F)
           NT SERVICE\TrustedInstaller:(OI)(CI)(IO)(F)
           NT AUTHORITY\SYSTEM:(F)
           NT AUTHORITY\SYSTEM:(OI)(CI)(IO)(F)
           BUILTIN\Administrators:(F)
           BUILTIN\Administrators:(OI)(CI)(IO)(F)
           BUILTIN\Users:(RX)
           BUILTIN\Users:(OI)(CI)(IO)(GR,GE)
           CREATOR OWNER:(OI)(CI)(IO)(F)
"@  -replace '(?m)^[A-Z]:(\\inetpub)', "$env:SYSTEMDRIVE`$1" -split '\r?\n'

$aclChangeRequired = $false
$aclOwnerChangeRequired = $false
$expectedOwner = "NT AUTHORITY\SYSTEM"

try {
    # Directory doesn't exist.
    if (-not(Test-Path -Path $targetPath -PathType Container)) {
        try {
            Write-Status -Status ACTION -Message "Creating directory '$targetPath'"
            New-Item -Path $targetPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $aclChangeRequired = $true; $aclOwnerChangeRequired = $true
            Write-Status -Status OK -Message "Directory created." -Indent 1
        }
        catch {
            throw "Unable to to create directory: $targetPath"
        }
    # Directory exists.
    } else {
        try {
            Write-Status -Status ACTION -Message "Checking permissions of '$targetPath'"

            $icaclsCurrent = icacls "$targetPath"
            if ($LASTEXITCODE -ne 0) { throw }


            $icaclsMatch = Compare-Object -ReferenceObject ($aclComparisonString | ForEach-Object {$_.Trim()} | Where-Object {$_.Length -gt 0}) `
                                          -DifferenceObject ($icaclsCurrent | Select-Object -SkipLast 2 | ForEach-Object {$_.Trim()} | Where-Object {$_.Length -gt 0}) `
                                          -IncludeEqual | Where-Object {$_.SideIndicator -ne "=="}


            if (-not ($null -eq $icaclsMatch)) {
                Write-Status -Status WARN -Message "Permissions require updating." -Indent 1
                $aclChangeRequired = $true
            } else {
                Write-Status -Status OK -Message "Permissions verified." -Indent 1
            }

            Write-Status -Status ACTION -Message "Checking the owner of '$targetPath'"

            $currentOwner = (Get-Acl $targetPath -ErrorAction Stop).Owner

            if ($currentOwner -ine $expectedOwner) {
                Write-Status -Status WARN -Message "Ownership requires updating." -Indent 1
                $aclOwnerChangeRequired = $true
            } else {
                Write-Status -Status OK -Message "Ownership verified." -Indent 1
            }
        }
        catch {
            Write-Status -Status WARN -Message "Unable to determine current permissions. Assuming an update is required." -Indent 1
            $aclChangeRequired = $true; $aclOwnerChangeRequired = $true
        }

        # Early exit if we've determined that no changes are required.
        if (-not ($aclChangeRequired -or $aclOwnerChangeRequired)) {
            Write-Status -Status OK -Message "No changes are required."
            exit 0
        }

        Write-Status -Status ACTION -Message "Checking contents of '$targetPath'"

        # If the directory isn't empty, provide a warning of the limited scope of the changes.
        if (Get-ChildItem -Path $targetPath -ErrorAction SilentlyContinue) {
            Write-Status -Status WARN -Message "'$targetPath' is not empty!" -Indent 1
            Write-Status -Status WARN -Message "Ownership change to '$expectedOwner' (default setting) will only apply to the parent directory ($targetPath)." -Indent 1
            Write-Status -Status WARN -Message "This is to prevent any potential issues with permissions that have been manually applied." -Indent 1
            Write-Status -Status INFO -Message "Please press any key to acknowledge..."
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        # Directory exists and is empty.
        } else {
            Write-Status -Status OK -Message "'$targetPath' exists and is empty."
        }
    }

    try {
        Write-Status -Status ACTION -Message "Importing necessary permissions"

        # Create a temporary file for use with icacls restore.
        $aclFile = New-TemporaryFile -ErrorAction Stop
        Set-Content -Value $aclImportString -Path $aclFile -Encoding unicode -Force -ErrorAction Stop

        # icacls "C:\" /restore path\to\file.tmp
        $result = icacls "$env:SystemDrive\" /restore $aclFile.FullName 2>&1

        if ($LASTEXITCODE -ne 0) { throw $result } else {
            Write-Status -Status OK -Message "Permissions successfully imported." -Indent 1
        }
    } catch {
        throw "Failed to import permissions for '$targetPath'. Error $($_.Exception.Message)."
    } finally {
        # Remove the temporary file.
        $aclFile | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Write-Status -Status ACTION -Message "Setting owner of '$targetPath' to '$expectedOwner'"

    try {
        # Set the owner of inetpub to 'NT AUTHORITY\SYSTEM'.
        $result = icacls $targetPath /SetOwner "SYSTEM" 2>&1

        if ($LASTEXITCODE -ne 0) { throw $result } else {
            Write-Status -Status OK -Message "Owner successfully set." -Indent 1
        }
    }
    catch {
        throw "Failed to set owner for '$targetPath'. Error: $($_.Exception.Message)"
    }
} catch {
    Write-Status -Status FAIL -Message $_.Exception.Message -Indent 1
    exit 1
} finally {
    Write-Status -Status OK -Message "Script execution complete."
    Write-Host "`nPress any key to continue..."
    # Pause on exit.
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}