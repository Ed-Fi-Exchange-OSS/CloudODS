# Resetting Cloud ODS Data

If you wish to reset the ODS database but want to avoid full reinstallation, you
can do so using the BACPAC files distributed with the Cloud ODS.
  
Each version of the Cloud ODS is distributed with BACPAC files containing schema
and data. These files are version-specific so you should take care to download
the version that matches the Cloud ODS you are installing. The following
databases should be created from the BACPAC files (be sure to replace the
correct version number in the URL):

* [EdFi\_Ods\_Minimal_Template](https://odsassets.blob.core.windows.net/public/CloudOds/deploy/release/\{version}\/EdFi_Ods_Minimal_Template.bacpac)
* [EdFi\_Ods\_Populated_Template](https://odsassets.blob.core.windows.net/public/CloudOds/deploy/release/\{version}\/EdFi_Ods_Populated_Template.bacpac)

You can import either the Minimal or Populated BACPAC files (linked above) over
top of your EdFi\_Ods\_Production database, depending on what data you want in
your database. Once the import has been completed, you will need to manually
grant the following permissions on the EdFi\_Ods\_Production database:

| DB User | Role(s) |
|--|--|
| EdFiOdsAdminApp | db\_datareader, db\_datawriter |
| EdFiOdsProductionApi | db\_datareader, db\_datawriter |

_Back to the [User's Guide Table of Contents](user-guide-toc.md)_
