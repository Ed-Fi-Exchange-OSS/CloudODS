# Configuring Azure Security Settings

## Admin App Security

By default, the Admin App is publicly available on the internet as are the ODS
APIs. We recommend that implementers consider securing the Admin App behind a
firewall, as typically its availability is restricted to a few individuals in an
organization. Instructions on security settings in Azure can be found under
Microsoft's Azure App Service Security pages.

The ODS API is typically publicly available, as vendor systems need to connect
to it. However, implementers should consider if additional security for the API
is required, and set rules as appropriate.

## Azure SQL

### Availability

By default, the instance of SQL server installed does not have a publicly
accessible IP address. To use SQL Server Management Studio (or other tools) to
access the Cloud ODS databases, you will need to create a firewall rule on that
resource in Azure. Please consult the Microsoft documentation on SQL Database
Firewall Rules.

### Encryption

With respect to security in the SQL environment, there are 3 areas of interest
for encryption:

* Hardware: Microsoft does not publish information on hardware-level encryption
  (e.g. whole-disk encryption) on the servers that run Azure.
* Application Storage: Azure SQL supports Transparent Data Encryption which
  encrypts data stored in an Azure SQL database physical files. TDE also applies
  to any backups of the database in question. This is a optional feature that is
  enabled within the ARM templates that deploy the Cloud ODS for all databases
  (Admin, Security, Sandbox, Production, and template DBs).
* Network/Transport: Azure SQL requires network-level encryption (i.e. SSL) at
  all times, so all traffic between apps and Azure SQL is secure. This is
  managed by Microsoft with no option to disable.

For more information, please consult
https://docs.microsoft.com/en-us/azure/sql-database/sql-database-security-overview

## Azure Websites

Microsoft provides SSL certificates to secure all Azure websites, provided those
websites are accessed via their *.azurewebsites.net URL. Implementers may choose
to add their own hostnames and SSL certificates post-deployment.

The Cloud ODS Admin App implements application level measures to require all
connections to the website run over SSL. The SSL requirement is built in code
and cannot be disabled for release builds (debug builds DO NOT require SSL).

The Cloud ODS API URLs provided in interfaces and via configuration also
reference SSL connection requirement (HTTPS URLs), though the ODS API code does
not require this by default and the URLs can be changed. We recommend that all
clients use HTTPS when using the APIs.

_Back to the [User's Guide Table of Contents](user-guide-toc.md)_
