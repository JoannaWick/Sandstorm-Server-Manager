# Sandstorm Server Manager
## Created for Insurgency Sandstorm 1.21 by Joanna Wick
### Version: 1.1.0
### Date: 2026-10-20

This package can Install/Add one or more Insurgency Sandstorm Server without the need to use Virtual Machines. It will keep mods updated, monitor players and restart downed servers automatically.

This project utilizes **LiteDB**, an embedded NoSQL document store for .NET.

* **Project Homepage:** [litedb.org](https://www.litedb.org/)
* **Source Code:** [GitHub - litedb-org/LiteDB](https://github.com/litedb-org/LiteDB)
* **License:** [MIT License](https://github.com)

This project utilizes **System.Buffers (4.6.1)**, a performance-critical resource pooling library provided by Microsoft.

* **Project Homepage:** [NuGet Gallery | System.Buffers](https://www.nuget.org/packages/System.Buffers/ "System.Buffers NuGet")
* **Source Code:** [GitHub - dotnet/maintenance-packages](https://github.com/dotnet/maintenance-packages "System.Buffers Source Code")
* **License:** [MIT License](https://github.com "Microsoft Maintenance Packages License")

This project utilizes **LiteDB.Studio**, the official graphical user interface tool for viewing and editing LiteDB v5 databases.

* **Project Homepage:** [litedb.org](https://www.litedb.org/ "LiteDB Homepage")
* **Source Code:** [GitHub - litedb-org/LiteDB.Studio](https://github.com/litedb-org/LiteDB.Studio "LiteDB.Studio GitHub Repo")
* **License:** [MIT License](https://github.com "LiteDB.Studio License")

### These videos are out of date but will give you an idea how to use this software until I can create new videos.  There have been a number of additions since these videos were made like a Unified Mod Directory where all mods for all servers are stored, one server software install used by all servers, disabling install servers and restoring user.json backups for each server.

You can Ctrl+Click or Cmd+Click to open video in a new tab

Watch the Sandstorm Server Manager First Run Video (Click Image to view)

[![Watch the Sandstorm Server Manager First Run Video](https://img.youtube.com/vi/xYBcZUzaKzs/0.jpg)](https://www.youtube.com/watch?v=xYBcZUzaKzs)

Watch the Sandstorm Manager Install New Server Video (Click Image to view)

[![Watch the Sandstorm Manager Install New Server Video](https://img.youtube.com/vi/Ub1nKeVgjBg/0.jpg)](https://www.youtube.com/watch?v=Ub1nKeVgjBg)

Watch theSandstorm Manager Import Existing Server (Click Image to view)

[![Watch the Sandstorm Manager Import Existing Server Video](https://img.youtube.com/vi/N59Fhv_-2Ks/0.jpg)](https://www.youtube.com/watch?v=N59Fhv_-2Ks)

Watch the Sandstorm Taskbar Video (Click Image to view)

[![Watch the Sandstorm Taskbar Video](https://img.youtube.com/vi/rs4zWuSRro8/0.jpg)](https://www.youtube.com/watch?v=rs4zWuSRro8)

Watch the Sandstorm Manager Other Selections Video (Click Image to view)

[![Watch the Sandstorm Manager Other Selections Video](https://img.youtube.com/vi/rDycwelK0tw/0.jpg)](https://www.youtube.com/watch?v=rDycwelK0tw)

Watch the Update Sandstorm Base Server Files Video (Click Image to view)

[![Watch the Update Sandstorm Base Server Files Video](https://img.youtube.com/vi/hau98xyawX4&t/0.jpg)](https://www.youtube.com/watch?v=hau98xyawX4&t)

Watch the Sandstorm Server Reboot Countdown Video (Click Image to view)

[![Watch the Sandstorm Server Reboot Countdown Video](https://img.youtube.com/vi/scxf6CNCILM/0.jpg)](https://www.youtube.com/watch?v=scxf6CNCILM)

Watch the Sandstorm Download Progress Bar Video (Click Image to view)

[![Watch the Sandstorm Download Progress Bar Video](https://img.youtube.com/vi/JNZ5WfJ0BCU/0.jpg)](https://www.youtube.com/watch?v=JNZ5WfJ0BCU)

Watch the Sandstorm Taskbar Toggle Video (Click Image to view)

[![Watch the Sandstorm Taskbar Toggle Video](https://img.youtube.com/vi/NYzJWfBCPtw/0.jpg)](https://www.youtube.com/watch?v=NYzJWfBCPtw)

Joanna Wick's Sandstorm Website (Click image to go to website)

[![Joanna Wick's Sandstorm Website](http://sandstorm.dworks.work/images/banner3.jpg)](https://sandstorm.dworks.work)

## Detailed Overview

Bullet Points for Sandstorm Server Manager (more detailed information later)

1. Install Multiple Sandstorm Servers on a single computer without needing to use Virtual Machine Software.  You can have as many servers installed and managed by this software as you have drive space and CPU ability.
2. Unified Mod Storage shared by all servers.  Instead of having a mod storage directory for each server there is not a single location.  Servers that use the same mods will now share the mods stored in that single location.  The mod doesn't have to be downloaded for each server that uses it.  This saves on drive storage a premium on a Remote Host.  My 4 servers went from 312GB to 134GB for mod storage.
3. Single Sandstorm Server install used by all servers in the Sandstorm Manager.  You will save 5GB of storage for each added server over the first one.  Instead of 20GB for 4 servers you still only use 5GB of storage for all 4.
4. First execution of Sandstorm Manager will automatically check to see if UE4 Prerequisites and required .NET files are installed.  If not the UE4 Prerequisites will be installed from the initial Sandstorm Server download.  The .NET files will be downloaded from Microsoft and installed.  **IMPORTANT: The 2.0 and 3.5 .NET files from Microsoft can take more than 10 minutes to download.  It can look like it is hung but it is not.
5. Installing a New Server is easy and fairly painless as you are taken through each step required and you are allowed to edit all .ini/.txt files during the process.  The initial server uses a default Game.ini and you should modify it to fit your needs.  You will be taken through the Configuration progress to finish setting up your server.
6. Importing an Existing Server is just as easy.  You will be ask to find the location of the InsurgencyServer.exe using a File GUI.  Once located the admin.txt, mapcycle.txt, motd.txt, Game.ini and Engin.ini will be copied to the Server Manager.  The you will be asked to locate the user.json file using a File GUI.  When located it will be copied to the Server Manager.  When this is copied you will not need to request a new Security Code from mod.io.  Next you will be asked to locate the state.json which will let the Sandstorm Manager know where you mods are located.  You mods will be copied to the UnifiedMods directory so they will not be downloaded again.  You will be taken through the Configuration progress to finish setting up your server.
7. The TCP/UDP Ports will be opened for each server during installation or importation.  You can change those ports at any time using the Sandstorm Manager and when changed they will be automatically opened for you.
8. You can Remove any server from the Server List.  This will not delete the server or mods but only the entry in the Server List.
9. You can ENABLE or DISABLE any installed server.  If you have a server causing problems, wanting to work on it or just want it off you can easily DISABLE it.  When the Server Launcher is started you will be notified of any DISABLED servers before launching any others.
10. Unsubscribing server mods is easy in the Server Manager.  Just select your server and all Subscribed mods will be shown.  Select any mods you would like to unsubcribe.  You will be given a change to abort after selecting.  If the mods you are unsubscribing are not being used by any other Server they will be deleted from the UnifiedMods directory freeing space.
11. If one of your servers refuses to connect to mod.io your user.json might be corrupted.  There are 11 backup user.json files you can pick from to restore and possible get your server up without requesting a new Security Code.
12. No need to use Windows Task Scheduler to reboot your servers on a regular basis.  You can now set as many Reboot Times as you would like and all servers will be rebooted at that time without having to reboot the computer itself.  **IMPORTANT:  You should have one reboot scheduled every day.  During reboot the Sandstorm Server software updated if needed and any mods will automatically be updated before launching each server.  All players on all servers will be sent Chat Messages starting 5 minutes before reboot every 30 seconds letting them know mow much time is left before reboot.
13. Server Analytics is included that tracks all players on every server showing when they joined, total play time, how many times they have joined for each server.  Also, each server will show graphs of total unique players per hour and per day.  You can even look at past histories of hourly and daily unique players.
14. Master Rcon Dashboard is included and all commands are supported and you can easily switch from server to server using a dropdown menu.
15. Included is a dynamically updated Server Dashboard that shows each server.  Each server will display Server Name, Current Map, Player Count/Max Players and all players on the server (Name, ID, IP Address and Score).  The window will stay the same size but the information inside the window will dynamically resize so everything fits without a scroll bar.
16. If any server crashes it will automatically restart so you do not have to be around to restart the server.
17. A Sandstorm Taskbar is included that will allow you to easily reboot a server or call up other items like RCon Dashboard and Sever Analytics.  You can set the Sandstorm Taskbar to minimize to a button after all servers have started.

That is a quick overview of what is included.  

## Installation & Setup

Provide step-by-step instructions on how to install and run your distribution.

1. Download the latest release from the [Mod.io]([link-to-releases](https://mod.io/g/insurgencysandstorm/m/sandstorm-server-manager#description)) page.
2. Extract the files to your desired location where you want all servers and mods to be stored.
3. Run Start_Server_Manager.bat to install a New Server or Add an Existing Server
4. Once your server(s) are setup Run Start_Server_Launcher.bat to start and monitor all of your Sandstorm Servers.

### If you see the following message when you run the script enter A or Y.

> Execution Policy Change

> The execution policy helps protect you from scripts that you do not trust. Changing the execution policy might expose
> you to the security risks described in the about_Execution_Policies help topic at

> http://go.microsoft.com/fwlink/?LinkID=135170. Do you want to change the execution policy?

> [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"):

Change Log
==========

1.1.0 (2026-10-20)

    1. [CHANGED] Mod Updater: The Download Progress Code has been re-written.  Some people were experiencing red errors being displayed slowing down downloads.  This should fix those errors.
    2. [ADDED] Mod Updater: When mod has been unsubscribed it will delete the mod if none of the other servers are subscribed freeing drive space.
    3. [FIXED] Mod Updater: If multiple servers were subscribed to the same mod only one will download and install it to the UnifideMods directory.
    4. [ADDED] Taskbar: Disable Server Button will kill a currently running server and then set it to Disabled so it will not start next reboot.
    5. [ADDED] When updating with a new version of Server Manager the startSandstormServer.bat will be copied to the Insurgency\steamapps\common\sandstorm_server directory overwriting the older version if new.  Updating to the latest version is easy.  Just copy the Sandstorm_Server_Manager to the existing directory overwritting everything in there.  None of the server configurations or mods will be changed.
    6. [CHANGED] Info Monitor: Moved Log Stream Parsing after Rcon processing to try and prevent players that have logged out from staying in the Server Dashboard display.
    7. [ADDED] Server Launcher: If a server reboots more than 4 times without being successful the server will be DISABLED to prevent further boot looping until the admin can investigate
    8. [ADDED] Server Launcher: Added check for "Warning: OSS: Async task 'FOnlineAsyncTaskSteamCreateServer bWasSuccessful: 0' failed" which signals server boot failure if in the last 20 lines of the log.
    9. [CHANGED] Server Launcher: Changed check for running servers to determine if not running then launch server.
    10. [CHANGED] Info Monitor: Changed the loop structure used by the Info Monitor to scan through server logs for player connects and disconnects.  The old method could drop lines from the stream.
    
1.0.0 (2026-10-16)

    1. Initial Release 
    

To Do
=====

    1. Add toggle to disable mod updates when server launches
    2. Server Dashboard will sometimes miss a player leaving and not remove them from the player list

       
