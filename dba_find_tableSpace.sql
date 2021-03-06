USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[dba_find_tableSpace]    Script Date: 07/09/2018 09:18:34 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ###################################################################################
--
-- Author:			Haden Kingsland
--
-- Date:			1st November 2012
--
-- Description :	To collect database table growth using sp_spaceused and 
--					sp_MSForEachTable. This is logged to a table and kept for a rolling
--					30 days.
--
--					delete from DBAdmin.dba.DB_TableSpace where RunDate < GETDATE()-30
--
--					EXEC sp_MSForEachTable 'EXEC sp_spaceused ''?'''
--
-- ###################################################################################

-- exec dbadmin.dba.dba_find_tableSpace
-- truncate table [dba].[DB_TableSpace]

--select * from [dba].[DB_TableSpace]
--order by databasename, tablename, rundate asc

--use [DBAdmin]

/********************************************************************************************************************/
-- Disclaimer...
--
-- This script is provided for open use by Haden Kingsland (theflyingDBA) and as such is provided as is, with
-- no warranties or guarantees.
-- The author takes no responsibility for the use of this script within environments that are outside of his direct
-- control and advises that the use of this script be fully tested and ratified within a non-production environment
-- prior to being pushed into production.
-- This script may be freely used and distributed in line with these terms and used for commercial purposes, but
-- not for financial gain by anyone other than the original author.
-- All intellectual property rights remain solely with the original author.
--
/********************************************************************************************************************/

ALTER PROCEDURE [dba].[dba_find_tableSpace]
AS

BEGIN

SET NOCOUNT ON;

DECLARE @SQL varchar(8000)

SELECT @SQL = '
IF ''@'' <> ''model'' AND ''@'' <> ''tempdb''
BEGIN
USE [@] EXECUTE sp_MSForEachTable ''INSERT INTO DBAdmin.dba.DB_TableSpace 
(TableName, NumRows, Reserved, DataUsed, IndexUsed, Unused) EXEC sp_spaceused ''''?'''';
UPDATE DBAdmin.dba.DB_TableSpace SET SchemaName = LEFT(''''?'''', CHARINDEX(''''.'''', ''''?'''', 1) - 2) 
WHERE SchemaName IS NULL;
UPDATE DBAdmin.dba.DB_TableSpace SET DatabaseName = ''''@'''' WHERE DatabaseName IS NULL; ''
END
'

EXEC sp_MSforeachdb @SQL, '@'

UPDATE DBAdmin.dba.DB_TableSpace
SET SchemaName = REPLACE(SchemaName, '[', '')

END;

