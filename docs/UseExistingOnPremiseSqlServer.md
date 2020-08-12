# Using an Existing On-Premise SQL Server

By default the Cloud ODS install script will create and manage an Azure SQL
server and databases for you. Azure SQL also happens to be the single largest
expense in a Cloud ODS installation. If your organization has access to database
administration expertise and existing license agreements for MS SQL Server, or
if you simple want hands-on control of your student databases, the steps
outlined below will help you configure your Cloud ODS to use a self-managed SQL
Server.

## Cloud ODS Installation

If you've chosen to run the Cloud ODS against your own SQL Server, the install
script should be run with the _-UseMyOwnSqlServer_ switch, as outlined
in [Installing the Cloud ODS and API](install-guide.md). For performance reasons it's
strongly recommended that you run your SQL Server on an appropriately-sized
Virtual Machine in the same Azure Region as your Cloud ODS. Microsoft has some
[helpful
documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-windows-sql-performance)
on this topic.

## SQL Server Configuration

The steps in this section should be performed PRIOR to running the Cloud ODS
installation script

### Administrative User

You'll need an administrative user account (i.e., a user in the role sysadmin)
whose credentials can be provided to the setup script. Therefore, this account
must be established prior to running the setup script.

The AdminApp will make use of an administrative account during first-time and
post-upgrade setup, but under normal circumstances, the ODS components will run
under non-privileged accounts.

### Database Setup

A Cloud ODS makes use of several different databases. Each of these databases
must either be created or imported prior to running the First-Time Setup in the
AdminApp. Once created, the First-Time Setup process will manage creating logins
and configuring access roles for each application in the Cloud ODS.

The following databases should be created but can be left empty:

* EdFi_Admin
* EdFi_Security
* EdFi\_Ods\_Production

See [SQL Docs: Create a Database](https://msdn.microsoft.com/en-us/library/ms186312.aspx)
for further detail about creating a new SQL Server database.

Each version of the Cloud ODS is distributed with BACPAC files containing schema
and data. These files are version-specific so you should take care to download
the version that matches the Cloud ODS you are installing. The following
databases should be created from the BACPAC files (be sure to replace the
correct version number in the URL):

*  [EdFi\_Ods](https://odsassets.blob.core.windows.net/public/CloudOds/deploy/release/\{version\}/EdFi_Ods.bacpac)
* [EdFi\_Ods\_Minimal_Template](https://odsassets.blob.core.windows.net/public/CloudOds/deploy/release/\{version\}/EdFi_Ods_Minimal_Template.bacpac)
* [EdFi\_Ods\_Populated_Template](https://odsassets.blob.core.windows.net/public/CloudOds/deploy/release/\{version\}/EdFi_Ods_Populated_Template.bacpac)

Instructions for importing BACPAC files to your SQL Server can be found
[here](https://msdn.microsoft.com/en-us/library/hh710052.aspx).

## Network Configuration

The steps in this section should be performed AFTER you've run the Cloud ODS
installation script, but PRIOR to running the AdminApp First-Time setup process.

Once your SQL Server and databases have been configured, you'll need to
configure network access for the Cloud ODS websites to your SQL Server.

The recommended approach to secure access between your Cloud ODS websites and
SQL Server is to configure an Azure VNET. Configuration specifics are left up to
the reader, though this
[article](https://docs.microsoft.com/en-us/azure/app-service-web/web-sites-integrate-with-vnet)
gives a thorough walkthrough.

## Admin App First Time Setup

This final step should be run AFTER your Network Configuration has been
completed.

With the above configuration in place, proceed with the First-Time Setup in the
Cloud ODS Admin App. The setup script will provide the AdminApp URL where you
can login and continue the process of bringing your Cloud ODS online.

_Back to the [User's Guide Table of Contents](user-guide-toc.md)_
