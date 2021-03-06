USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[old_database_filesize_alert]    Script Date: 07/09/2018 09:56:47 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[old_database_filesize_alert]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 08/01/2007
-- Version	: 01:00
--
-- Desc		: To report on database file size and alert if over
--			  80% of the maximum allowed.
--
-- Modification History
-- ====================
--
--
--
--#############################################################
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

DECLARE @name varchar(20);
DECLARE @percentage_used int;
DECLARE @current_size int;
DECLARE @max_size int;
DECLARE @database_name varchar(10);
DECLARE @database_id int;
DECLARE @MESSAGE_BODY nvarchar(250);
DECLARE @MESSAGE_BODY2 nvarchar(250);
DECLARE @MESSAGE_BODY3 nvarchar(250);
DECLARE @MESSAGE_BODY4 nvarchar(500);
DECLARE @MESSAGE_SUBJECT varchar(100);
DECLARE @filename varchar(520);

DECLARE @MailProfileName VARCHAR(50);

-- SELECT @database_name = DB_NAME()

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

	DECLARE check_databases CURSOR FOR

	select 
	name, 
	database_id
	from sys.databases
        where name not like '%temp%'
		and name <> 'model'
		and name <> 'master'
		and name <> 'msdb'
	order by name;

-- Open the cursor.
	OPEN check_databases;

-- Loop through the update_stats cursor.

	FETCH NEXT
	   FROM check_databases
	   INTO @database_name, @database_id;

	WHILE @@FETCH_STATUS = 0
	BEGIN

	PRINT @database_name
	PRINT @database_id

-- nested cursor for data file size 

	DECLARE database_file_size CURSOR FOR

	--	select 
	--		round ( ( (f.size * 8/1024)* 100) /(f.max_size * 8/1024),1 ), 
	--			 f.name,
	--			(f.size * 8/1024),
	--			(f.max_size * 8/1024)
	--			from sys.database_files f
	--			where f.name not like '%log%'
	--			and f.max_size > 0
	--			order by f.name;

	select 
			round ( ( (f.size * 8/1024)* 100) /(f.maxsize * 8/1024),1 ), 
				 f.name,
				(f.size * 8/1024),
				(f.maxsize * 8/1024),
				 f.filename
				from sys.sysaltfiles f
				where f.name not like '%log%'
				and f.maxsize > 0
				and f.dbid = @database_id
				order by f.name;


		-- Open the cursor.
		OPEN database_file_size;

		-- Loop through to check current database file sizes.

			FETCH NEXT
				FROM database_file_size
				INTO @percentage_used, @name, @current_size, @max_size, @filename;

			WHILE @@FETCH_STATUS = 0
			BEGIN

				-- if database file size is over 80% of the maximum allowed, then send an alert.

				if @percentage_used >= 80

					BEGIN

						PRINT @percentage_used;
						PRINT @name;

						SET @MESSAGE_SUBJECT='WARNING !!!! Datafile maximum size alert for database... ' + @database_name + '  on ' + @@SERVERNAME
						SET @MESSAGE_BODY='Datafile ' + RTRIM(@name) + ' for database ' + RTRIM(@database_name) + ' is currently ' + CONVERT(CHAR(3),@percentage_used) + '% of the maximum size allowed.'
						SET @MESSAGE_BODY2=' Current Size is ' + RTRIM(CONVERT(CHAR(10),@current_size)) + ' (Mb) of a maximum allowed ' + RTRIM(CONVERT(CHAR(10),@max_size)) + ' (Mb).'
						SET @MESSAGE_BODY3='    Full datafile path is: ' + @filename + '.'
						SET @MESSAGE_BODY4 = @MESSAGE_BODY + @MESSAGE_BODY2 + @MESSAGE_BODY3 + '  Please inform Technical Support if out of hours'

						EXEC msdb.dbo.sp_notify_operator 
						@profile_name = @MailProfileName, 
						@name=N'DBA-Alerts', 
						@subject = @MESSAGE_SUBJECT, 
						@body= @MESSAGE_BODY4 ;

					END

				FETCH NEXT FROM database_file_size INTO @percentage_used, @name, @current_size, @max_size, @filename;

			END
		-- Close and deallocate the cursor.

			CLOSE database_file_size;
			DEALLOCATE database_file_size;


	FETCH NEXT FROM check_databases INTO @database_name, @database_id;

	END

	-- Close and deallocate the cursor.

	CLOSE check_databases;
	DEALLOCATE check_databases;

END

