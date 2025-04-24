# Reset inetpub

[KB5055523](https://support.microsoft.com/en-gb/topic/april-8-2025-kb5055523-os-build-26100-3775-277a9d11-6ebf-410c-99f7-8c61957461eb) created an `inetpub` folder at `%SYSTEMDRIVE%\inetpub` due to [CVE-2025-2120](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2025-21204).

If you, like myself, deleted this folder before discovering that it was created for security related concerns then this procedure is for you.

This method allows you to restore the folder and appropriate permissions (at least to the parent folder) without the need to enable / disable IIS.

**Administrator elevation is required.**

## Instructions

1. Clone this repo (or download / extract) to your desired location.
2. Execute `Run.bat`.

## Script Actions
1. Create `%SYSTEMDRIVE%\inetpub` if it doesn't exist.
1. Assign temporary ownership of the directory to the ` BUILTIN\Administrators` group.
1. Import the appropriate ACL permissions.
1. Assign ownership of the directory to `NT AUTHORITY\SYSTEM`.

## Permissions
    C:\inetpub NT SERVICE\TrustedInstaller:(F)
           NT SERVICE\TrustedInstaller:(OI)(CI)(IO)(F)
           NT AUTHORITY\SYSTEM:(F)
           NT AUTHORITY\SYSTEM:(OI)(CI)(IO)(F)
           BUILTIN\Administrators:(F)
           BUILTIN\Administrators:(OI)(CI)(IO)(F)
           BUILTIN\Users:(RX)
           BUILTIN\Users:(OI)(CI)(IO)(GR,GE)
           CREATOR OWNER:(OI)(CI)(IO)(F)
