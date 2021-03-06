USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[dba_no_full_backup_within_8_days_report]    Script Date: 07/09/2018 09:20:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- #######################################################################################
--
-- Author:			Haden Kingsland
--
-- Date:			23rd September 2015
--
-- Description :	To report on databases that have had no FULL backup within
--					the past 8 days!
--
-- Modification History
-- ####################
--
--
-- exec dbadmin.dba.dba_no_full_backup_within_8_days_report 'hkingsland@laingorourke.com;rfinney@laingorourke.com'
--
-- #######################################################################################
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

ALTER procedure [dba].[dba_no_full_backup_within_8_days_report]
@recipient_list varchar(2000) -- list of people to email
as

BEGIN

DECLARE		@MailProfileName VARCHAR(50),		
			@ERR_MESSAGE varchar(200),
			@ERR_NUM int,
			@MESSAGE_BODY varchar(2000),
			@MESSAGE_BODY2 varchar(1000),
			@p_error_description varchar(300),
			@NewLine CHAR(2),
			@Q CHAR(1),
			@tableHTML VARCHAR(MAX),
			@tableHTML2 VARCHAR(MAX),
			@lineHTML VARCHAR(MAX),
			@lineHTML2 VARCHAR(MAX),
			@start_table VARCHAR(MAX),
			@start_table2 VARCHAR(MAX),
			@TR varchar(20),
			@END	 varchar(30),
			@END_TABLE varchar(30),
			@ENDTAB varchar(20),
			--@recipient_list	varchar(1000),
			@email varchar(100),
			@failsafe VARCHAR(100), -- failsafe operator to email
			@value varchar(30),
			@mailsubject varchar(200),
			@propertyid int,
			@userid bigint, 
			@dbname varchar(100),
			@createDate datetime,
			@lastbackupdate datetime,
			@action varchar(50),
			@backupageh int,
			@backupaged int,
			@instancename varchar(100),
			@server varchar(50),
			--@recipient_list varchar(2000),
			@td varchar(25);

SET @NewLine = CHAR(13) + CHAR(10) 
SET @Q = CHAR(39) 

-- initialize variables (otherwise concat fails because the variable value is NULL)

set @lineHTML = '' 
set @tableHTML = ''
set @start_table = ''
--set @days = 10

SET @tableHTML =
		'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset// EN">' +
		'<html>' +
		'<LANG="EN">' +
		'<head>' +
		'<TITLE>SQL Administration</TITLE>' +
		'</head>' +
		'<body>'
		
set @start_table = '<font color="black" face="Tahoma" >' + 
	'<CENTER>' + 
	'<H1><font size=4>Databases with no FULL backups within SQL instance... '+ @@servername + '</font></H1>' +
	'<table border="1">' +
	'<tr BGCOLOR="green">' + 
	-- list all table headers here
	'<th BGCOLOR="#0066CC" width="100%" colspan="6">Database Details</th>'+'</tr>' + 
	'<tr>' + 
	--'<th BGCOLOR="#99CCFF">Server Name</th>' + 
	'<th BGCOLOR="#99CCFF">Instance</th>' +
	'<th BGCOLOR="#99CCFF">Database Name</th>' + 
	'<th BGCOLOR="#99CCFF">Last Backup Date</th>' +
	'<th BGCOLOR="#99CCFF">Backup Age (Hours)</th>' + 
		'<th BGCOLOR="#99CCFF">Backup Age (Days)</th>' + 
	'<th BGCOLOR="#99CCFF">Action</th>' + 
	'</tr>'

SET @TR = '</tr>'
SET @ENDTAB = '</table></font>'
--SET @END = '</table></font></body></html>'
SET @END_TABLE = '</table></font>'
SET @END = '</body></html>'

SET @mailsubject   = 'The following Databases have had no FULL backup for at least 8 days from... ' + CONVERT(VARCHAR(11),GETDATE(),113)

SELECT @MailProfileName = name
FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
where name like '%DBA%'

PRINT @MailProfileName

	BEGIN TRY
	
DECLARE build_report CURSOR
FOR
SELECT
   CONVERT( CHAR(100 ), SERVERPROPERTY ('Servername')) AS Server,
   MAX(BS.backup_finish_date) AS last_db_backup_date,
   bs.database_name as 'Database Name',
   DATEDIFF( hh, MAX(BS.backup_finish_date ), GETDATE ()) AS [Backup Age (Hours)],
   DATEDIFF( DAY, MAX(BS.backup_finish_date ), GETDATE ()) AS [Backup Age (Days)],
   'Please Investigate as FULL backup is outside of excepted range!'
FROM    msdb.dbo.backupset BS
left outer join sys.databases SD on sd.name = bs.database_name -- in case databases no longer exist but backup history does!
WHERE     BS.type = 'D'  
--AND SD.state not in (1,2,3,6,10)
and SD.is_read_only <> 1
GROUP BY BS.database_name
HAVING (MAX( BS.backup_finish_date) < DATEADD (day, - 8, GETDATE ())) 
order by last_db_backup_date
		-- Open the cursor.
		OPEN build_report;

		-- Loop through the update_stats cursor.

		FETCH NEXT
		   FROM build_report
		   INTO		@instancename, 
		   			@lastbackupdate,
					@dbname,
					@backupageh,
					@backupaged,
					@action

		--PRINT 'Fetch Status is ... ' + CONVERT(VARCHAR(10),@@FETCH_STATUS)

		WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement fails or the row is beyond the result set
		BEGIN

			IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
			BEGIN

				set @lineHTML = RTRIM(LTRIM(@lineHTML)) + 
								'<tr>' + 
								'<td>' + ISNULL(cast(@instancename as varchar(100)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@dbname as varchar(50)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(left( convert (char(20) ,@lastbackupdate, 113 ), 17),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@backupageh as varchar(5)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@backupaged as varchar(5)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@action as varchar(40)),'NOVAL') + '</td>'
								+ '</tr>'
								

				set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=orange>' );
	
				
				print @lineHTML

			END
		
		FETCH NEXT
		   FROM build_report
		   INTO		@instancename, 
		   			@lastbackupdate,
					@dbname,
					@backupageh,
					@backupaged,
					@action

		END

		-- Close and deallocate the cursor.

		CLOSE build_report;
		DEALLOCATE build_report;

-- 03/02/2012 -- changed to check the contents of the @linehtml variable, so that it will not generate an email if there
-- is not data to display.

		IF (@lineHTML != '' and @lineHTML is not NULL)
		BEGIN
	
			set @tableHTML = RTRIM(LTRIM(@tableHTML)) + @start_table + RTRIM(LTRIM(@lineHTML)) + @END_TABLE + @END

			-- as the <td> tags are auto-generated, I need to replace then with a new <td>
			-- tag including all the required formatting.

			--set @tableHTML = REPLACE( @tableHTML, '<td>', '<td BGCOLOR=yellow>' );
			
			print @tableHTML
		
			IF @recipient_list IS NULL 
			or @recipient_list = ''
			BEGIN
			
				SELECT @recipient_list = email_address
				FROM msdb..sysoperators
				WHERE name = 'DBA-Alerts' -- Name of main required operator
				
				IF @recipient_list IS NULL
				BEGIN
							
					EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
												 N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
												 N'AlertFailSafeOperator',
												 @failsafe OUTPUT,
												 N'no_output'

					SELECT @recipient_list = email_address
					FROM msdb..sysoperators
					WHERE name = @failsafe
					                             
				END
			END
			
			PRINT @recipient_list
			
				EXEC msdb.dbo.sp_send_dbmail
					@profile_name = @MailProfileName,
					@recipients = @recipient_list,
					@body_format = 'HTML',
					@importance = 'HIGH',
					@body = @tableHTML,
					@subject = @mailsubject
					
		END
		
	END TRY

	BEGIN CATCH
	
	print 'Error Code is ... ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message is ... ' + @ERR_MESSAGE
	
		SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
		SET @MESSAGE_BODY='Error running the ''dba_no_full_backup_within_8_days_report'' for the... ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(30)))) + ' instance'
		+  '. Error Code is ... ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message is ... ' + @ERR_MESSAGE
		SET @MESSAGE_BODY2='The script failed whilst running against the... ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(30)))) + ' instance'
		SET @MESSAGE_BODY = @MESSAGE_BODY -- + @MESSAGE_BODY3

		EXEC msdb.dbo.sp_notify_operator 
			@profile_name = @MailProfileName, 
			@name=N'DBA-Alerts',
			@subject = @MESSAGE_BODY2, 
			@body= @MESSAGE_BODY
	
	-- If for some reason this script fails, check for any temporary
	-- tables created during the run and drop them for next time.
	
		IF object_id('tempdb..#temp_vm_create') IS NOT NULL
		BEGIN
		   DROP TABLE #temp_vm_create
		END

	END CATCH
	
END

