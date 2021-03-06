USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[dba_server_disk_space_report]    Script Date: 07/09/2018 09:29:51 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ###################################################################################
--
-- Author:			Haden Kingsland
--
-- Date:			2nd October 2012
--
-- Description :	To report on datafile growth from the [dba].[check_server_disk_space]
--					stored procedure which is run at 05:15 everyday. It checks the 
--					dba.drivespace table within the DBAdmin database and reports on 
--					current disk size and available free space.
--
-- ###################################################################################
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

--exec dbadmin.dba.dba_server_disk_space_report 1,'hkingsland@laingorourke.com'

ALTER procedure [dba].[dba_server_disk_space_report]
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
			@email varchar(100),
			@value varchar(30),
			@mailsubject varchar(200),
			@propertyid int,
			@userid bigint, 
			@property_value varchar(1000),
			@output VARCHAR(1000),
			@failsafe VARCHAR(100),
			@type varchar(10), 
			@drive char(1),
			@freespace int,
			@totalsize int,
			@percentfree int,
			@MetricDate datetime,
			@servername varchar(50),
			@period	int,
			--@days int,
			--@recipient_list	varchar(1000),
			@td varchar(25);

SET @NewLine = CHAR(13) + CHAR(10) 
SET @Q = CHAR(39) 

-- initialize variables (otherwise concat fails because the variable value is NULL)
set @lineHTML = '' 
set @tableHTML = ''
set @start_table = ''
--set @days = 20

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
	'<H1><font size=4>DB Server Mount Point Sizes for SQL instance... '+ @@servername + ' as of 05:30am on ' + 
	CONVERT(VARCHAR(11),GETDATE(),113) + '</font></H1>' +
	'<table border="1">' +
	'<tr BGCOLOR="green">' + 
	-- list all table headers here
	'<th BGCOLOR="#0066CC" width="100%" colspan="6">DB Server Mount Point Sizes</th>'+'</tr>' + 
	'<tr>' + 
	'<th BGCOLOR="#99CCFF">Drive Letter</th>' + 
	'<th BGCOLOR="#99CCFF">Metric Date</th>' +
	'<th BGCOLOR="#99CCFF">Free Space</th>' +
	'<th BGCOLOR="#99CCFF">Total Size</th>' + 
	'<th BGCOLOR="#99CCFF">Percentage Free</th>' +
	'<th BGCOLOR="#99CCFF">Servername</th>' + 
	'</tr>'
				

SET @TR = '</tr>'
SET @ENDTAB = '</table></font>'
--SET @END = '</table></font></body></html>'
SET @END_TABLE = '</table></font>'
SET @END = '</body></html>'

SET @mailsubject   = 'Current Drive Space for ' + LTRIM(left(@@SERVERNAME,(len(@@SERVERNAME))-(charindex('\',reverse(@@SERVERNAME))))) + ' on ' + CONVERT(VARCHAR(11),GETDATE(),113)

SELECT @MailProfileName = name
FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
where name like '%DBA%'

PRINT @MailProfileName

	BEGIN TRY
	
--Select 'Data' as Type, DBName, OrigSize,CurSize,GrowthAmt,MetricDate from DBAdmin.[dbo].[DBGrowthRate_data]
--where growthamt > = convert(varchar(5),5.0)
--union all
--Select 'TX Log' as Type, DBName, OrigSize,CurSize,GrowthAmt,MetricDate from DBAdmin.[dbo].[DBGrowthRate_TXLog]
--where growthamt > = convert(varchar(5),5.0)
--order by DBName, MetricDate desc

DECLARE build_report CURSOR
FOR
select   dsp.drive,
         max(dsp.freespace),
         dsp.totalsize,
         dsp.percentfree,
         max(dsp.metricdate),
         dsp.servername
from     DBAdmin.dba.drivespace as dsp
where DATEPART(dd,dsp.metricdate) = DATEPART(dd,getdate()) -- only return information for the run of the current morning
--where    DATEdiff(mi, dsp.metricdate, GetDate()) > @days -- return results for 'n' minutes ago
--where  DATEdiff(dd, dsp.metricdate, GetDate()) > @days -- return results for the previous day
group by dsp.drive, dsp.totalsize, dsp.percentfree, dsp.servername
order by dsp.drive asc;

		-- Open the cursor.
		OPEN build_report;

		-- Loop through the update_stats cursor.

		FETCH NEXT
		   FROM build_report
		   INTO  @drive, 
		   @freespace,
		   @totalsize,
		   @percentfree,
		   @metricdate,
		   @servername

		--PRINT 'Fetch Status is ... ' + CONVERT(VARCHAR(10),@@FETCH_STATUS)

		WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement fails or the row is beyond the result set
		BEGIN

			IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
			BEGIN

				set @lineHTML = RTRIM(LTRIM(@lineHTML)) + 
								'<tr>' + 
								'<td>' + ISNULL(cast(@drive as varchar(5)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(left(convert (char(20) ,@MetricDate, 113 ), 17),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@freespace as varchar(10)) + ' MB','NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@totalsize as varchar(10)) + ' MB','NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@percentfree as varchar(5))+ ' %','NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@servername as varchar(50)),'NOVAL') + '</td>'
								+ '</tr>'
								
				IF @percentfree <= 10
				BEGIN
					set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=#FF0000>' ); -- red
				END
				IF (@percentfree > 10 
				and @percentfree <= 40)
				BEGIN
					set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=#FFFF00>' ); -- yellow
				END
				IF @percentfree > 40 
				BEGIN
					set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=#66FF33>' ); -- green
				END
				
				print @lineHTML

			END
		
		FETCH NEXT
		   FROM build_report
		   INTO  @drive, 
		   @freespace,
		   @totalsize,
		   @percentfree,
		   @metricdate,
		   @servername

		END

		-- Close and deallocate the cursor.

		CLOSE build_report;
		DEALLOCATE build_report;
	
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

	END CATCH
	
END

