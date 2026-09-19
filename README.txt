DOCUMENTS BACKUP FOR WINDOWS
============================

What it does
------------
When the registered external drive is connected, a visible progress window
backs up the current Windows user's Documents folder. Unchanged files are
skipped. New and changed files are copied. Files deleted from the PC remain in
the backup.

Backups are kept separate:
  External drive\PC Backup\COMPUTER-NAME\WINDOWS-USER\Documents

Install (once, as an administrator)
-----------------------------------
1. Extract this ZIP to a normal folder.
2. Connect the external HDD.
3. Double-click Install.cmd.
4. Approve the Windows administrator prompt.
5. Select the external HDD and click Install.

The installer starts the watcher for the installing user. Every other Windows
user gets it automatically the next time they sign in. The external drive is
recognized by its volume serial number, so its drive letter may change.

Uninstall
---------
Double-click Uninstall.cmd and approve the administrator prompt. Uninstalling
does not delete backups already stored on the external drive.

Important notes
---------------
* Windows PowerShell 5.1 and Windows 10/11 are required.
* Keep free space available on the external drive.
* This is a one-way, non-destructive file backup, not version history. If a
  file is changed, the previous backup copy is replaced.
* The progress window must finish before the drive is unplugged. If it is
  unplugged early, reconnecting it retries the backup.
* Files another program has locked may fail. Reconnecting the drive later
  retries them.
* Treat the HDD as a backup, not the only copy of important files.

