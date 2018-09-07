--#######################################################################################################
--
-- Date			: 07/09/2018
-- DBA			: Haden Kingsland
-- Description	: To check recovery status of a database after instance re-start
--
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
--  Modification History...
--
-- Useage...
-- exec dba.usp_check_database_restore_status 'DBAdmin'
--
create procedure [dba].[usp_check_database_restore_status]
@DBName VARCHAR(64)

as

BEGIN

	DECLARE @ErrorLog AS TABLE
	([LogDate]     CHAR(24), 
	 [ProcessInfo] VARCHAR(64), 
	 [TEXT]        VARCHAR(MAX)
	);
	INSERT INTO @ErrorLog
	EXEC master..sp_readerrorlog 
		 0, 
		 1, 
		 'Recovery of database', 
		 @DBName;
	SELECT TOP 5 [LogDate], 
				 SUBSTRING([TEXT], CHARINDEX(') is ', [TEXT])+4, CHARINDEX(' complete (', [TEXT])-CHARINDEX(') is ', [TEXT])-4) AS PercentComplete, 
				 CAST(SUBSTRING([TEXT], CHARINDEX('approximately', [TEXT])+13, CHARINDEX(' seconds remain', [TEXT])-CHARINDEX('approximately', [TEXT])-13) AS FLOAT)/60.0 AS MinutesRemaining, 
				 CAST(SUBSTRING([TEXT], CHARINDEX('approximately', [TEXT])+13, CHARINDEX(' seconds remain', [TEXT])-CHARINDEX('approximately', [TEXT])-13) AS FLOAT)/60.0/60.0 AS HoursRemaining, 
				 [TEXT]
	FROM @ErrorLog
	ORDER BY [LogDate] DESC;

END;
