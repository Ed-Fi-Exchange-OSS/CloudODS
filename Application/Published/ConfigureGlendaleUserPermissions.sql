IF DATABASE_PRINCIPAL_ID('EdFiOdsProductionApi') IS NULL 
BEGIN
    CREATE USER [EdFiOdsProductionApi] FOR LOGIN [EdFiOdsProductionApi] WITH DEFAULT_SCHEMA=[dbo]
END

EXEC sp_addrolemember @rolename = 'db_datareader', @membername = 'EdFiOdsProductionApi'
EXEC sp_addrolemember @rolename = 'db_datawriter', @membername = 'EdFiOdsProductionApi'

GRANT execute ON SCHEMA :: dbo TO EdFiOdsProductionApi


IF DATABASE_PRINCIPAL_ID('EdFiOdsAdminApp') IS NULL 
BEGIN
    CREATE USER [EdFiOdsAdminApp] FOR LOGIN [EdFiOdsAdminApp] WITH DEFAULT_SCHEMA=[dbo]
END


EXEC sp_addrolemember @rolename = 'db_datareader', @membername = 'EdFiOdsAdminApp'
EXEC sp_addrolemember @rolename = 'db_datawriter', @membername = 'EdFiOdsAdminApp'

GRANT execute ON SCHEMA :: dbo TO EdFiOdsAdminApp
