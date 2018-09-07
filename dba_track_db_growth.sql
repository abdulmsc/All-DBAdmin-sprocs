USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[dba_track_db_growth]    Script Date: 07/09/2018 09:31:38 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dba].[dba_track_db_growth]
(
@dbnameParam sysname = NULL
)
AS
BEGIN

--#####################################################################################################################
--
-- Author	: Haden Kingsland
-- Date		: 27/10/2009
-- Version	: 01:00
--
-- Desc		: Run this script in the master database to create the stored procedure. Once it is created,
--		you could run it from any of your user databases. If the first parameter (database name) is
--		not specified, the procedure will use the current database. 
--
--		Example 1:
--		To see the file growth information of the current database:
--
--		EXEC sp_track_db_growth
--
--		Example 2:
--		To see the file growth information for pubs database:
--	
--		EXEC sp_track_db_growth 'pubs'
--
-- Modification History
-- ====================
--
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

DECLARE @dbname sysname

/* Work with current database if a database name is not specified */

SET @dbname = COALESCE(@dbnameParam, DB_NAME())

SELECT	CONVERT(char, backup_start_date, 111) AS [Date], --yyyy/mm/dd format
	CONVERT(char, backup_start_date, 108) AS [Time],
	@dbname AS [Database Name], [filegroup_name] AS [Filegroup Name], logical_name AS [Logical Filename], 
	physical_name AS [Physical Filename], CONVERT(numeric(9,2),file_size/1048576) AS [File Size (MB)],
	Growth AS [Growth Percentage (%)]
FROM
(
	SELECT	b.backup_start_date, a.backup_set_id, a.file_size, a.logical_name, a.[filegroup_name], a.physical_name,
		(
			SELECT	CONVERT(numeric(5,2),((a.file_size * 100.00)/i1.file_size)-100)
			FROM	msdb.dbo.backupfile i1
			WHERE 	i1.backup_set_id = 
						(
							SELECT	MAX(i2.backup_set_id) 
							FROM	msdb.dbo.backupfile i2 JOIN msdb.dbo.backupset i3
								ON i2.backup_set_id = i3.backup_set_id
							WHERE	i2.backup_set_id < a.backup_set_id AND 
								i2.file_type='D' AND
								i3.database_name = @dbname AND
								i2.logical_name = a.logical_name AND
								i2.logical_name = i1.logical_name AND
								i3.type = 'D'
						) AND
				i1.file_type = 'D' 
		) AS Growth
	FROM	msdb.dbo.backupfile a JOIN msdb.dbo.backupset b 
		ON a.backup_set_id = b.backup_set_id
	WHERE	b.database_name = @dbname AND
		a.file_type = 'D' AND
		b.type = 'D'
		
) as Derived
WHERE (Growth <> 0.0) OR (Growth IS NULL)
ORDER BY logical_name, [Date]

END

