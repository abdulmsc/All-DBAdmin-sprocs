USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[dba_disk_growth_report]    Script Date: 07/09/2018 08:54:12 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- #######################################################################################
--
-- Author:			Haden Kingsland
--
-- Date:			2nd February 2012
--
-- Description :	To report on database and transaction log growth for a given
--					period, based upon the data held in the following DBAdmin
--					tables... dbo.DBGrowthRate_Data & dbo.DBGrowthRate_TXLog.
--					The data for these tables being populated daily by the following
--					2 SQL Agent jobs...
--					Track Database & TX Log Growth Individually Daily
--					Track Database Growth Daily
--					...which both run at 05:30 every morning.
--
-- Modification History
-- ####################
--
-- 03/02/2012 - HJK	- Changed to check the contens of the @linehtml variable, so that 
--					  it will not generate an email if there is not data to display.
--
-- exec dbadmin.dba.dba_disk_growth_report 3, 'anyperson@anymail.com'
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

ALTER procedure [dba].[dba_disk_growth_report]
 (
    @days	int, -- number of days to report back from
    @recipient_list varchar(2000) -- list of people to email
 )
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
			@value varchar(30),
			@mailsubject varchar(200),
			@propertyid int,
			@userid bigint, 
			@property_value varchar(1000),
			@output VARCHAR(1000),
			@failsafe VARCHAR(100),
			@type varchar(10), 
			@dbname varchar(100),
			@OrigSize decimal(10,2),
			@CurSize decimal(10,2),
			@GrowthAmt varchar(100),
			@MetricDate datetime,
			@period	int,
			--@days int,
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
	'<H1><font size=4>Database & TX Log Growth/Shrinkage of more than 5% for the '+ @@servername + ' instance since 05:30 on ' + 
	CONVERT(VARCHAR(11),GETDATE()-@days,113) + '</font></H1>' +
	'<table border="1">' +
	'<tr BGCOLOR="green">' + 
	-- list all table headers here
	'<th BGCOLOR="#0066CC" width="100%" colspan="6">Database Growth Details</th>'+'</tr>' + 
	'<tr>' + 
	'<th BGCOLOR="#99CCFF">Type</th>' + 
	'<th BGCOLOR="#99CCFF">Metric Date</th>' +
	'<th BGCOLOR="#99CCFF">Database Name</th>' + 
	'<th BGCOLOR="#99CCFF">Original Size</th>' +
	'<th BGCOLOR="#99CCFF">Current Size</th>' +
	'<th BGCOLOR="#99CCFF">Growth Amount</th>' + 
	'</tr>'

SET @TR = '</tr>'
SET @ENDTAB = '</table></font>'
--SET @END = '</table></font></body></html>'
SET @END_TABLE = '</table></font>'
SET @END = '</body></html>'

SET @mailsubject   = 'The following Databases have grown or shrunk more than 5% since 05:30 on ' + CONVERT(VARCHAR(11),GETDATE()-@days,113)

SELECT @MailProfileName = name
FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
where name like '%DBA%'

PRINT @MailProfileName

	BEGIN TRY
	
DECLARE build_report CURSOR
FOR
Select 'Data' as Type, DBName, OrigSize,CurSize,GrowthAmt,MetricDate from DBAdmin.[dbo].[DBGrowthRate_data]
where growthamt > = convert(varchar(5),5.0)
and MetricDate > getdate()-@days
union all
Select 'TX Log' as Type, DBName, OrigSize,CurSize,GrowthAmt,MetricDate from DBAdmin.[dbo].[DBGrowthRate_TXLog]
where growthamt > = convert(varchar(5),5.0)
and MetricDate > getdate()-@days
order by Type, DBName, MetricDate desc

-- Show Total Growth for period stored
--Select 'Data' as Type, DBName, 
---- strip the MB from the end of the GrowthAmt column to allow for conversion to a decimal.
--SUM(cast(LTRIM(RTRIM(SUBSTRING(GrowthAmt,1,LEN(GrowthAmt)-2))) as decimal(10,2))) as 'Total Growth'
--,min(metricdate) as 'Start Period'
--,max(metricdate) as 'End Period'
----LTRIM(RTRIM(SUBSTRING(GrowthAmt,1,LEN(GrowthAmt)-2)))
--from DBAdmin.[dbo].[DBGrowthRate_data]
--where growthamt > = convert(varchar(5),5.0)
--group by DBName
--union all
--Select 'TX Log' as Type, DBName, 
---- strip the MB from the end of the GrowthAmt column to allow for conversion to a decimal.
--SUM(cast(LTRIM(RTRIM(SUBSTRING(GrowthAmt,1,LEN(GrowthAmt)-2))) as decimal(10,2))) as 'Total Growth'
--,min(metricdate) as 'Start Period'
--,max(metricdate) as 'End Period'
--from DBAdmin.[dbo].[DBGrowthRate_TXLog]
--where growthamt > = convert(varchar(5),5.0)
--group by DBName
--order by Type, DBName desc

		-- Open the cursor.
		OPEN build_report;

		-- Loop through the update_stats cursor.

		FETCH NEXT
		   FROM build_report
		   INTO  @type, 
		   @dbname,
		   @OrigSize,
		   @CurSize,
		   @GrowthAmt,
		   @MetricDate

		--PRINT 'Fetch Status is ... ' + CONVERT(VARCHAR(10),@@FETCH_STATUS)

		WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement fails or the row is beyond the result set
		BEGIN

			IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
			BEGIN

				set @lineHTML = RTRIM(LTRIM(@lineHTML)) + 
								'<tr>' + 
								'<td>' + ISNULL(cast(@type as varchar(100)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(left( convert (char(20) ,@MetricDate, 113 ), 17),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@dbname as varchar(50)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@OrigSize as varchar(20)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@CurSize as varchar(30)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@GrowthAmt as varchar(30)),'NOVAL') + '</td>'
								+ '</tr>'
								
				IF @type = 'Data'
				BEGIN
					set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=#CCCC33>' );
				END
				IF @type = 'TX Log'
				BEGIN
					set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=#33FF99>' );
				END
				
				print @lineHTML

			END
		
		FETCH NEXT
		   FROM build_report
		   INTO  @type, 
		   @dbname,
		   @OrigSize,
		   @CurSize,
		   @GrowthAmt,
		   @MetricDate

		END

		-- Close and deallocate the cursor.

		CLOSE build_report;
		DEALLOCATE build_report;

-- 03/02/2012 -- changed to check the contens of the @linehtml variable, so that it will not generate an email if there
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
		SET @MESSAGE_BODY='Error running the ''Database Growth Report'' ' 
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

