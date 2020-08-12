# Installing a Larger Sample Database

For testing or other reasons, you may want to install a larger sample database
than the one that ships with with the Cloud ODS (approximately 1000 student
dataset). The following instructions describe how to install the Glendale
database into the Cloud ODS (approximately 50,000 student dataset).

## Prerequisites

* Cloud ODS instance installed with first-time setup complete.  See: Installing
  the Cloud ODS and API
* Make note of the install-friendly name used during the above installation
  process (By default, this is EdFi ODS)
* The Glendale bacpac file is found at techdocs.ed-fi.org on the ED-FI ODS / API
  BINARY RELEASES section. You need to use the same version of the Cloud ODS
  instance deployed.
* If necessary, create a backup of your current EdFi_Ods_Production database, as
  this operation will overwrite all data

## Installation Process

1. Open a Powershell window and navigate to the directory containing the Cloud
   ODS templates and scripts (ex. C:\CloudOdsInstall)

```powershell
cd C:\CloudOdsInstall\
```

2. Deploy the Glendale dataset:  run .\Deploy-GlendaleDataset.ps1
   -InstallFriendlyName "[Friendly name of your Cloud ODS]" -GlendaleDatasetUrl
   "[Glendale baccpac URL]"

```powershell
.\Deploy-GlendaleDataSet.ps1 -InstallFriendlyName "Your EdFi ODS Install Friendly Name" -GlendaleDatasetUrl "URL to the Glendale bacpac file"
```

3. Wait for the deployment to process to complete.  The process can take quite a
   while: an hour or more is not out of the question. Once completed, you should
   see a new database in the Azure portal named "EdFi_Ods_Glendale"

*Note: this extra database is now accruing charges in your Azure account*

4. In the Azure portal, add a firewall rule for your current IP address to the
   Azure SQL server

![Azure control panel resource
view](images/InstallSampleDatabase-Resource.png)

![Azure control panel adding client IP
address](images/InstallSampleDatabase-AddClientIP.png)

5. Connect to the Azure SQL server via SQL Server Management Studio

![Login to SQL Server Management
Studio](images/InstallSampleDatabase-SQLMgmtStudio.png)

6. Click File -> Open, and select the ConfigureGlendaleUserPermissions.sql
   script from the directory containing the Cloud ODS scripts

![Locating the permission configuration
script](images/InstallSampleDatabase-ConfigureGlendalePermissions.png)

7. Run ConfigureGlendaleUserPermissions.sql script against the EdFi_Ods_Glendale
   database

![Executing the permission configuration
script](images/InstallSampleDatabase-ExecuteScriptOnGlendale.png)

If necessary, make a backup of EdFi_Ods_Production.

**Important Note: All data in this database will be lost in the next
operation!**

9. Click File -> Open: select SwitchODSToGlendale.sql

![Locating the script to move the
database](images/InstallSampleDatabase-SwitchODSToGlendale.png)

10. Disconnect and reconnect to SQL Server. This will enable you see the master
    database again.

11. Run SwitchODSToGlendale.sql against the master database in order to replace
    the current database with the Glendale dataset.  **When you run this script,
    all data in the current EdFi_Ods_Production database will be lost.**

![Executing the permission configuration
script](images/InstallSampleDatabase-ExecuteScriptOnMaster.png)

_Back to the [User's Guide Table of Contents](user-guide-toc.md)_
