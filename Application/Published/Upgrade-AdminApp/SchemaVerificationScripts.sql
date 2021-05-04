CREATE PROC SchemaValidation @Schema NVARCHAR(100)
AS
BEGIN

    DECLARE @Sql NVARCHAR(MAX) = '';

	--constraints
	SELECT @Sql = @Sql + 'ALTER TABLE '+ QUOTENAME(@Schema) + '.' + QUOTENAME(t.name) + ' DROP CONSTRAINT ' + QUOTENAME(f.name)  + ';' + CHAR(13)
	FROM sys.tables t 
		inner join sys.foreign_keys f on f.parent_object_id = t.object_id 
		inner join sys.schemas s on t.schema_id = s.schema_id
	WHERE s.name = @Schema
	ORDER BY t.name;

	--tables
	SELECT @Sql = @Sql + 'DROP TABLE '+ QUOTENAME(@Schema) +'.' + QUOTENAME(TABLE_NAME) + ';' + CHAR(13)
	FROM INFORMATION_SCHEMA.TABLES
	WHERE TABLE_SCHEMA = @Schema AND TABLE_TYPE = 'BASE TABLE'
	ORDER BY TABLE_NAME

    --schema
	SELECT @Sql = @Sql + 'DROP SCHEMA '+ QUOTENAME(@Schema) + ';' + CHAR(13)

	EXECUTE sp_executesql @Sql     
    
END
GO

EXEC SchemaValidation N'adminapp'
EXEC SchemaValidation N'adminapp_HangFire'

DROP PROCEDURE SchemaValidation