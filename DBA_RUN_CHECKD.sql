USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[DBA_RUN_CHECKDB]    Script Date: 07/09/2018 09:24:11 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[DBA_RUN_CHECKDB]

--#############################################################################
--
-- Author	: Haden Kingsland
-- Date		: 15/10/2015
-- Version	: 01:00
--
-- Desc		: To run a DBCC CHECKDB across all online databases. This has been written as the original, below process
--			  had issues when running the sp_MSforeachdb procedure and was missing some databases!
--
--	EXEC sp_MSforeachdb N'IF DATABASEPROPERTYEX(''?'', ''Collation'') IS NOT NULL
--
--	BEGIN
--
--		DBCC CHECKDB (?) WITH ALL_ERRORMSGS, EXTENDED_LOGICAL_CHECKS, DATA_PURITY
--
--	END' ;
--
-- Usage:
--
-- exec [dbadmin].[dba].[DBA_RUN_CHECKDB]
--
-- Modification History
-- ====================
--
-- 15/10/2015 -- Haden Kingsland	First cut of the procedure written
--
--##########################################################################################################################
--
-- Using the NULLIF() function to overcome divide by zero errors. 
-- Basically it compares 2 values, and if the first is equal to the second, it returns null, hence... NULLIF(). 
-- Usage is... NULLIF(passed in value,value to compare against), e.g... NULLIF(0,0).
-- In our case, if size or maxsize = 0, then it will return NULL and carry on rather than causing a divide by zero error. 
        
--##########################################################################################################################
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

AS 

BEGIN

DECLARE		
			@database_name varchar(200),
			@database_id bigint,
			@MESSAGE_BODY nvarchar(250),
			@MESSAGE_BODY2 nvarchar(250),
			@MESSAGE_BODY3 nvarchar(250),
			@MESSAGE_BODY4 nvarchar(500),
			@MESSAGE_BODY5 nvarchar(500),
			@MESSAGE_SUBJECT varchar(200),
			@command nvarchar(500),
			@ERR_MESSAGE varchar(400),
			@ERR_NUM bigint,
			@XPCMDSH_ORIG_ON varchar(1),
			@MailProfileName VARCHAR(50),
			@SQL varchar(500);

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

---------------------
-- Initialize variables
---------------------

set @XPCMDSH_ORIG_ON = ''
set @SQL = ''

--------------------------------------------------------------------------------------------------------------------
-- Check whether xp_cmdshell is turned off via Surface Area Configuration (2005) / Instance Facets (>2008)
-- This is best practice !!!!! If it is already turned on, LEAVE it on !!

-- turn on advanced options
	EXEC sp_configure 'show advanced options', 1 reconfigure 
	RECONFIGURE  

	CREATE TABLE #advance_opt (name VARCHAR(20),min int, max int, conf int, run int)
			INSERT #advance_opt
		EXEC sp_configure 'xp_cmdshell' -- this will show whether xp_cmdshell is turned on or not
				
	IF (select conf from #advance_opt) = 0 -- check if xp_cmdshell is turned on or off, if off, then turn it on
		BEGIN

			set @XPCMDSH_ORIG_ON = 'N' -- make a note that it is NOT supposed to be on all the time
			
			--turn on xp_cmdshell to allow operating system commands to be run
			EXEC sp_configure 'xp_cmdshell', 1 reconfigure
			RECONFIGURE
		END
	ELSE
		BEGIN
		 -- make a note that xp_cmdshell was already turned on, so not to turn it off later by mistake
			set @XPCMDSH_ORIG_ON = 'Y'
		END

-- drop the temporary table to tidy up after ourselves.

	IF EXISTS (
	select * from tempdb.sys.objects
	where name like '%advance_opt%'
	)
		BEGIN
			drop table #advance_opt
		END
		
--------------------------------------------------------------------------------------------------------------------

	DECLARE check_databases CURSOR FOR

	select 
	name, 
	database_id
	from sys.databases
	where database_id  NOT IN (3) -- ignore the model database
	and state in (0,4) -- online or suspect
	order by name;

-- Open the cursor.
	OPEN check_databases;

-- Loop through the update_stats cursor.

	FETCH NEXT
	   FROM check_databases
	   INTO @database_name, @database_id;


			WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement failed or the row is beyond the result set
			BEGIN

					IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
					BEGIN

						BEGIN TRY
						
							set @sql = 'DBCC CHECKDB ' + '(' + '[' + @database_name + ']' + ')' + ' WITH ALL_ERRORMSGS, EXTENDED_LOGICAL_CHECKS, DATA_PURITY'
						
							print @sql;
							exec (@sql);
						
						END TRY
						
						BEGIN CATCH
						
							SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();

							SET @MESSAGE_BODY='Failure running the DBCC CHECKDB job for ' + @database_name + ' Error Message = ' + @ERR_MESSAGE
							SET @MESSAGE_SUBJECT='Failure running the DBCC CHECKDB job for ' + @database_name + '  on ' + @@SERVERNAME
									
							EXEC msdb.dbo.sp_notify_operator 
								@profile_name = @MailProfileName, 
								@name=N'DBA-Alerts',
								@subject = @MESSAGE_SUBJECT,
								@body= @MESSAGE_BODY;
							
							print @MESSAGE_BODY
							print @MESSAGE_SUBJECT

						END CATCH
						
						--FETCH NEXT FROM check_databases INTO @database_name, @database_id;

					END -- end of @@fetchstatus if
					
					FETCH NEXT FROM check_databases INTO @database_name, @database_id;
			END


	-- Close and deallocate the cursor.

	CLOSE check_databases;
	DEALLOCATE check_databases;
	
-----------------------------------------------------------------------------------------------------------------------		
-- turn off advanced options

	IF @XPCMDSH_ORIG_ON = 'N'  -- if xp_cmdshell was NOT originally turned on, then turn it off 
	BEGIN

		-- turn on advanced options again just to ensure we can turn off xp_cmdshell!
		EXEC sp_configure 'show advanced options', 1 reconfigure 
		RECONFIGURE  

		--  turn off xp_cmdshell to dis-allow operating system commands to be run
		EXEC sp_configure 'xp_cmdshell', 0  reconfigure
		RECONFIGURE

		EXEC sp_configure 'show advanced options', 0 reconfigure
		RECONFIGURE
		
	END
-----------------------------------------------------------------------------------------------------------------------
	
END

