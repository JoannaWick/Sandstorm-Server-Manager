# Sandstorm Server Manager
## Created for Insurgency Sandstorm 1.21 by Joanna Wick
### Version: 1.0.0
### Date: 2026-10-16

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



## Installation & Setup

Provide step-by-step instructions on how to install and run your distribution.

1. Download the latest release from the [Releases](link-to-releases) page.
2. Extract the files to your desired location.
3. Run Start_Manage_Multi_Server.bat to install a New Server or Add an Existing Server
4. Once your server(s) are setup Run Start_Multi_Server_Launcher.bat to start and monitor all of your Sandstorm Servers.

### If you see the following message when you run the script enter A or Y.

> Execution Policy Change

> The execution policy helps protect you from scripts that you do not trust. Changing the execution policy might expose
> you to the security risks described in the about_Execution_Policies help topic at

> http://go.microsoft.com/fwlink/?LinkID=135170. Do you want to change the execution policy?

> [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"):

Change Log
==========

1.0.0 (2026-10-16)

    1. Initial Release 

To Do
=====

    1. Add Reboot Counter for each Server.  If a server reboots X number of times within 10 minutes the server is DISABLED
       to prevent boot looping until the Admin can resolve the issue.
       
