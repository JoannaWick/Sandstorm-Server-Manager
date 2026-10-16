# Sandstorm Server Manager
## Created for Insurgency Sandstorm 1.21 by Joanna Wick
### Version: 0.0.1
### Date: 2026-07-25

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

### 📦 Third-Party Redistributables
This release package includes the following third-party prerequisite installers to ensure runtime compatibility:

* **Prerequisite:** UE4PrereqSetup_x64.exe (Unreal Engine 4 Prerequisites)
* **Copyright Holder:** © Epic Games, Inc.
* **Licensing:** Distributed under the terms of the Epic Games Unreal Engine End User License Agreement (EULA). 
* **Purpose:** Deploys underlying engine runtime components (such as Microsoft Visual C++ redistributables and DirectX dependencies).

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

## Credits & Acknowledgements

* **[Your Name/Studio]** - Creator and developer of this project.
* This software uses components from **Unreal Engine** (© Epic Games, Inc.). 
* `UE4PrereqSetup_x64.exe` is a prerequisite installer provided by Epic Games, Inc. to configure required system runtimes. Learn more at [unrealengine.com](https://unrealengine.com).

## License

State your project's license here (e.g., MIT, GPL, or Proprietary/All Rights Reserved). 

*Note: The included Epic Games prerequisites remain subject to the Unreal Engine End User License Agreement (EULA).*

Change Log
==========

1.0.0 (2026-??-??)

    1. Initial Release 

To Do
=====

    1. Nothing at this time
