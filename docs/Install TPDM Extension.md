# Install TPDM Extension

Adds the TPDM extension to an existing Cloud ODS deploy

## Audience

This document is targeted at IT professionals with some experience in software deployments.
A minimal amount of experience with command prompts is necessary.
Some familiarity with Microsoft PowerShell is ideal.
The user should also be familiar with the Microsoft Azure portal and tools.

## Prerequisites

TODO

## Preparation

* Backup your current deployed databases.
* Use a folder for containing the extensions resources.
You can create an `Extension/` folder where you have saved your templates and scripts.

    ```powershell
    cd C:/CloudOdsInstall/Extensions
    ```

* download the latest [TPDM Extension](https://www.myget.org/F/ed-fi/api/v2/package/EdFi.Suite3.Ods.Extensions.TPDM/5.1.0) package.

* Change extension from nupkg to zip.
* Right-click the zip, click unblock, and unzip the package.
* Copy the `Artifacts/` folder to your extensions folder `C:/CloudOdsInstall/Extensions`

* download the EdFi.Db.Deploy Tool by running the following command:

    ```powershell
    dotnet tool install EdFi.Suite3.Db.Deploy --tool-path C:/CloudOdsInstall/ --version 2.1.0 --add-source https://www.myget.org/F/ed-fi/api/v3/index.json
    ```

    Additional install and usage information for the EdFi.Db.Deploy tool can also be found in the [Database Deploy Tool](https://techdocs.ed-fi.org/display/ODSAPIS3V510/Database+Deploy+Tool#DatabaseDeployTool-InstallingtheApplication) in the [Ed-Fi Tech Docs](https://techdocs.ed-fi.org/).

## Deploy TPDM to an existing ODS

Applying TPDM database scripts to an existing ODS can be done using the EdFi.Db.Deploy tool.
The EdFi.Db.Deploy tool has the following parameters.

### EdFi.Db.Deploy parameters

* Verb

    Currently supported verbs are `Deploy` and `WhatIf`.
    For this example we will use `Deploy`.

    ```powershell
    -Deploy
    ```

* Datbase Engine

    Currently supported engines are `SQLServer` and `PostgreSQL`.
    For this example we will use `SQLServer`.

    ```powershell
    -Engine "SQLServer"
    ```

* Database Type

    Currently supported database types  are `Admin`, `Security`, and `Ods`.
    For this example we will use `Security`, and `Ods`, but first we will use `Ods`

    ```powershell
    -Database "Ods"
    ```


* Database Connection String

    Install-friendly name or Resource group name of the old Ed-Fi ODS instance
    containing data that will be migrated: e.g. 'EdFi ODS'.  This instance must
    already exist.

    ```powershell
    -ConnectionString "server=<SERVER_NAME>; User ID=<USER_ID>; Password=<PASSWORD>; database=EdFi_Ods; Encrypt=True"
    ```

* Features

    Optional features to install, as comma-separated list

    ```powershell
    -Features "changes"
    ```

* FilePaths

    This is the path to the folder containing the extension `Artifact/` folder.
    The tool will automatically resolve script locations based off the `Database` and `Engine` parameters.
    For This example we want the path to the TPDM extension package downloaded above.

    ```powershell
    -FilePaths "C:/CloudOdsInstall/Extensions/"
    ```
