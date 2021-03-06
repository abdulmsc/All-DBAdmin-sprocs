USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[database_filesize_alert]    Script Date: 07/09/2018 08:31:34 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[database_filesize_alert]

--exec [dba].[new_database_filesize_alert]

--#############################################################################
--
-- Author	: Haden Kingsland
-- Date		: 27/03/2007
-- Version	: 01:00
--
-- Desc		: To report on database file size and alert if over
--			  80% of the maximum allowed. If there is enough
--			  available space on the mountpoint, then automatically
--			  extend the datafile by 20% of it's current size.
--
-- Modification History
-- ====================
--
-- 07/04/2009 -- Haden Kingsland	Swapped calculations around to cater for arithmetic overflow problems
--												related to unlimited maxsize values. Also added call to check whether 
--												xp_cmdshell is enabled, and turn it on and then off it not.
--
--##############################################################################

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

DECLARE		@name varchar(200),
			@percentage_used int,
			@current_size int,
			@max_size int,
			@database_name varchar(200),
			@database_id int,
			@MESSAGE_BODY nvarchar(250),
			@MESSAGE_BODY2 nvarchar(250),
			@MESSAGE_BODY3 nvarchar(250),
			@MESSAGE_BODY4 nvarchar(500),
			@MESSAGE_BODY5 nvarchar(500),
			@MESSAGE_SUBJECT varchar(100),
			@filename varchar(520),
			@size_to_grow int,
			@extra_growth int,
			@filename2 varchar(520),
			@output nvarchar(70),
			@output2 nvarchar(100),
			@output3 nvarchar(100),
			@output4 nvarchar(15),
			@result nvarchar(15),
			@mp_free_space int, -- in bytes
			@command nvarchar(500),
			@ERR_MESSAGE varchar(400),
			@ERR_NUM int,
			@XPCMDSH_ORIG_ON varchar(1),
			@MailProfileName VARCHAR(50);

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

---------------------
-- Initialize variables
---------------------

set @XPCMDSH_ORIG_ON = ''

--------------------------------------------------------------------------------------------------------------------
-- Check whether xp_cmdshell is turned off via Surface Area Configuration (2005) / Instance Facets (2008)
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
	and state = 0 -- online database only 
	and is_read_only = 0 -- in read/write mode
	order by name;

-- Open the cursor.
	OPEN check_databases;

-- Loop through the update_stats cursor.

	FETCH NEXT
	   FROM check_databases
	   INTO @database_name, @database_id;

	WHILE @@FETCH_STATUS = 0
	BEGIN

	--PRINT @database_name
	--PRINT @database_id

-- nested cursor for data file size 

	DECLARE database_file_size CURSOR FOR

	select 
			round ( ( (f.size * 8/1024)* 100) /((f.maxsize/1024) * 8),1 ), -- to cater for arithmetic overflow problems
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

				BEGIN TRY

				-- if database file size is over 80% of the maximum allowed, then send an alert.

				if @percentage_used >= 80

					BEGIN
					
					--set @filename = 'd:\sql\edm_live06\'--haden.txt'

					-- strip out full path from filename (returned from the earlier select)
					select left(@filename,(len(@filename))-(charindex('\',reverse(@filename))) )

					-- append dir to the file path
					set @filename2 = 'dir ' + @filename

					-- create a local temporary table and shell out to DOS using xp_cmdshell to do a dir on the mount point
					CREATE TABLE #DirResults (Diroutput NVARCHAR(500))
					INSERT #DirResults
					exec xp_cmdshell @filename2

					-- assign @output the value of the select that contains the file size in bytes
					select @output = diroutput from #dirresults
					where Diroutput like '%free%' 

					-- get the position of the first letter 'b' in from the end of the string, and then take this from
					-- the total length of the string to return the string without the right portion of text
					select @output2 = LTRIM(left(@output,(len(@output))-(charindex('b',reverse(@output))) ))
					from #dirresults 

					-- get the position of the last ')' in from the start of the string, and then take this from
					-- the total length of the string to return the string without the left portion of text
					select @output3 = RTRIM(right(@output2,(len(@output2))-(charindex(')',@output2)) ))

					-- get the position of the last ',' in from the end of the string, and then take this from
					-- the total length of the string to return the string without the last 3 characters (rounding up)
					-- to give a whole number in bytes
					select @output4 = RTRIM(left(@output3,(len(@output3))-(charindex(',',@output3)) ))

					-- remove all commas from the output
					set @result = LTRIM(replace(@output4,',',''))

					-- convert the nvarchar value into an integer for number manipulation
					set @mp_free_space = convert(integer, @result)

					-- drop the temporary table
					drop table #dirresults

					-- work out 30% of free space available and convert to Mb from bytes
					set @mp_free_space = ((@mp_free_space * 30)/100)/1024

					print @mp_free_Space

					-- set the size to grow as 20% of the files current size, and then add this
					-- to the maximum size to increase the files allowable growth.
					set @size_to_grow = round( (@max_size + ((@current_size * 20)/100)),1)

					-- calculate the 20% growth required from the current size
					set @extra_growth = (@current_size * 20)/100

					-- if the data file 20% extra to grow is less than 30% of the available free space
					-- on the mountpoint then resize the datafile
					If @mp_free_space > @extra_growth 
					begin
					
					set @command = 'alter database ' + '[' + @database_name + ']' + ' MODIFY FILE ( NAME = ' + @name + ', MAXSIZE = ' + CONVERT(CHAR(6),@size_to_grow) + ' )'
	
						-- print @command

							exec (@command);

							SET @MESSAGE_SUBJECT='FOR INFORMATION !! Datafile maximum size alert for database... ' + @database_name + '  on ' + @@SERVERNAME
							SET @MESSAGE_BODY='Datafile ' + RTRIM(@name) + ' for database ' + RTRIM(@database_name) + ' is currently ' + CONVERT(CHAR(3),@percentage_used) + '% of the maximum size allowed.'
							SET @MESSAGE_BODY2=' Current Size is ' + RTRIM(CONVERT(CHAR(10),@current_size)) + ' (Mb) of a maximum allowed ' + RTRIM(CONVERT(CHAR(10),@max_size)) + ' (Mb).'
							SET @MESSAGE_BODY3='    Full datafile path is: ' + @filename + '.'
							SET @MESSAGE_BODY4 = @MESSAGE_BODY + @MESSAGE_BODY2 + @MESSAGE_BODY3 + '  Datafile Maxsize has been automatically extended by 20% of the current size. NO ACTION REQUIRED !!'

					end
					else
					if @mp_free_space < @extra_growth 
					begin

							SET @MESSAGE_SUBJECT='WARNING !!!! Datafile maximum size alert for database... ' + @database_name + '  on ' + @@SERVERNAME
							SET @MESSAGE_BODY='Datafile ' + RTRIM(@name) + ' for database ' + RTRIM(@database_name) + ' is currently ' + CONVERT(CHAR(3),@percentage_used) + '% of the maximum size allowed.'
							SET @MESSAGE_BODY2=' Current Size is ' + RTRIM(CONVERT(CHAR(10),@current_size)) + ' (Mb) of a maximum allowed ' + RTRIM(CONVERT(CHAR(10),@max_size)) + ' (Mb).'
							SET @MESSAGE_BODY3='    Full datafile path is: ' + @filename + '.'
							SET @MESSAGE_BODY5=' Calculated datafile maxsize is great than 30% of remaining disk space on mountpoint - Unable to extend file. ACTION IS REQUIRED !!'
							SET @MESSAGE_BODY4 = @MESSAGE_BODY + @MESSAGE_BODY2 + @MESSAGE_BODY3 + @MESSAGE_BODY5
					end

						EXEC msdb.dbo.sp_notify_operator 
						@profile_name = @MailProfileName, 
						@name=N'DBA-Alerts', 
						@subject = @MESSAGE_SUBJECT, 
						@body= @MESSAGE_BODY4 ;

					END

				END TRY			

				BEGIN CATCH
							
					SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();

					SET @MESSAGE_BODY='Error altering ' + @database_name + ' Error Message = ' + @ERR_MESSAGE
					SET @MESSAGE_SUBJECT='Failure to alter database maxsize parameter for ' + @name + ' in ' + @database_name + '  on ' + @@SERVERNAME
							
					EXEC msdb.dbo.sp_notify_operator 
						@profile_name = @MailProfileName, 
						@name=N'DBA-Alerts',
						@subject = @MESSAGE_SUBJECT,
						@body= @MESSAGE_BODY;

				END CATCH	

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
	
-----------------------------------------------------------------------------------------------------------------------		
-- turn off advanced options

	IF @XPCMDSH_ORIG_ON = 'N'  -- if xp_cmdshell was NOT originally turned on, then turn it off 
	BEGIN

		-- turn on advanced options
		EXEC sp_configure 'show advanced options', 1 reconfigure 
		RECONFIGURE  

		--  turn off xp_cmdshell to dis-allow operating system commands to be run
		EXEC sp_configure 'xp_cmdshell', 0  reconfigure
		RECONFIGURE

		EXEC sp_configure 'show advanced options', 0 reconfigure
		RECONFIGURE
		
	END
-----------------------------------------------------------------------------------------------------------------------
				
END;

