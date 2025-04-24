# Reset inetpub

[KB5055523](https://support.microsoft.com/en-gb/topic/april-8-2025-kb5055523-os-build-26100-3775-277a9d11-6ebf-410c-99f7-8c61957461eb) has introduced the creation of an `inetpub` folder at `%SYSTEMDRIVE%\inetpub` as a mitigation for [CVE-2025-2120](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2025-21204).

If, like me, you deleted this folder before realising its purpose in addressing security concerns, this guide is for you.

The procedure outlined here enables you to restore the folder and configure the appropriate permissions (at least for the parent folder), without needing to enable and disable IIS.

Please note: 
1. **Administrator privileges are required**.
1. The default permissions / inheritance settings are applied to the parent folder (`%SYSTEMDRIVE%\inetpub`).
1. Only the parent folder will have the ownership transferred to `NT AUTHORITY\SYSTEM`.

## Instructions

1. Open an **elevated** PowerShell window.
1. Run the following command:

       powershell -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/mmotti/Reset-inetpub/refs/heads/main/Reset.ps1' | iex"

## Script Actions
1. Create `%SYSTEMDRIVE%\inetpub` if it doesn't already exist.
1. Import the appropriate ACL permissions for `%SYSTEMDRIVE%\inetpub`.
1. Assign ownership of the directory to `NT AUTHORITY\SYSTEM`.

## Permissions
The following permissions are captured from the empty `inetpub` directory (created by [KB5055523](https://support.microsoft.com/en-gb/topic/april-8-2025-kb5055523-os-build-26100-3775-277a9d11-6ebf-410c-99f7-8c61957461eb)).

**`icacls` export:** see [acls.txt](acls.txt)

**`icacls` permission summary:**

    C:\inetpub NT SERVICE\TrustedInstaller:(F)
           NT SERVICE\TrustedInstaller:(OI)(CI)(IO)(F)
           NT AUTHORITY\SYSTEM:(F)
           NT AUTHORITY\SYSTEM:(OI)(CI)(IO)(F)
           BUILTIN\Administrators:(F)
           BUILTIN\Administrators:(OI)(CI)(IO)(F)
           BUILTIN\Users:(RX)
           BUILTIN\Users:(OI)(CI)(IO)(GR,GE)
           CREATOR OWNER:(OI)(CI)(IO)(F)