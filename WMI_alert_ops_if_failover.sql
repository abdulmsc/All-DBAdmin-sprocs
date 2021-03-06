USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[WMI_alert_ops_if_failover]    Script Date: 07/09/2018 10:56:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[WMI_alert_ops_if_failover]

-- ################################################################################################
--
-- Ref		: http://www.microsoft.com/technet/prodtechnol/sql/2005/mirroringevents.mspx
-- 
-- Author	: Haden Kingsland
-- Date		: 03/02/2009
-- Version	: 01:00
--
-- Desc		:	To email selected operators when a database fails over.
--					To be run in conjuction with the Alert Ops if Failover "DB NAME"
--					 Agent Alert.
--
-- ##########################################
-- EXAMPLE DATABASE_MIRRORING_STATE_CHANGE ALERT TEXT
-- ##########################################
--
--			  It is triggered by the following WMI events ...
--			  SELECT * FROM DATABASE_MIRRORING_STATE_CHANGE 
--			  WHERE state = integer
--			  States we are interested in are as follows:
--			
--			  5  = Connection with Principal Lost (for mirror server)
--            6  = Connection with mirror lost
--			  7  = Manual failover
--            8  = Automatic failover
--			  9  = Mirroring suspended
--	          10 = No Quorum (unable to connect to the witness server)
--
-- ############################
-- sys.database_mirroring
-- ############################
--
--			    State of the mirror database and of the database mirroring session.
--				sys.database_mirroring
--
--				0 = Suspended
--				1 = Disconnected from the other partner
--				2 = Synchronizing 
--				3 = Pending Failover
--				4 = Synchronized
--				5 = The partners are not synchronized. Failover is not possible now.
--				6 = The partners are synchronized. Failover is potentially possible. 	 
--				NULL = Database is inaccessible or is not mirrored. 
--
-- ############################
-- DATABASE_MIRRORING_STATE_CHANGE
-- ############################
--
--				Table 3: Properties of a Database Mirroring State Change WMI Event 
--				------------------------------------------------------------------ 
--
--				The time that the event occurred. Note that the WMI DateTime type and 
--				the SQL Server datetime type are not compatible.
--				------------------
--				StartTime DateTime
--
--				The server name
--				---------------
--				ComputerName String
--
--				The name of the instance in which the event occurred 
--				("MSSQLSERVER" for the default instance).
--				------------------
--				SQLInstance String
--
--				The name of the mirrored database
--				-------------------
--				DatabaseName String
--
--				The ID of the mirrored database
--				-----------------
--				DatabaseID Sint32
--
--				A number that represents the state—see Table 2 for details
--				------------
--				State Sint32
--
--				Text that describes the old and new states, in the following 
--				format: <old state name> -> <new state name>
--				---------------
--				TextData String
--
-- http://technet.microsoft.com/en-us/library/ms175575(SQL.90).aspx
--
--################################################################################
--Note that you must enable the use of tokens in SQL Server Agent jobs. 
--To do so, do the following:
--################################################################################

--1.Right-click the SQL Server Agent folder in Object Explorer and click Properties 
--on the shortcut menu.
 
--2.In the SQL Server Agent Properties dialog box, in Select a page, 
--click Alert System.
 
--3.At the bottom of the page, select the "Replace tokens for all job 
--responses to alerts" check box.
 
--4.Restart the SQL Server Agent service.
--
-- ####################################
--	EXAMPLE OF AN AGENT JOB STEP TO CALL THIS SP
-- ####################################
--
--DECLARE @RC int;
--DECLARE @starttime datetime;
--DECLARE @alert_text nvarchar(1000);
--DECLARE @alert_state int;
--DECLARE @name nvarchar(30);
--DECLARE @job_name varchar(128);
--DECLARE @SQLInstance nvarchar(25);
--DECLARE @ComputerName nvarchar(20);
--DECLARE @SessionLoginName nvarchar(25);
--
--set @starttime = getdate() 
--set @alert_text = '$(ESCAPE_NONE(WMI(TextData)))'
--set @alert_state = '$(ESCAPE_NONE(WMI(State)))'
--set @name = '$(ESCAPE_NONE(WMI(DatabaseName)))'
--set @SQLInstance = '$(ESCAPE_NONE(WMI(SQLInstance)))'
--set @ComputerName = '$(ESCAPE_NONE(WMI(ComputerName)))'
--set @SessionLoginName = '$(ESCAPE_NONE(WMI(SessionLoginName)))'
--
--set @job_name = 'Test WMI Alert'
--
--print @starttime 
--print @alert_text
--print @alert_state 
--print @name 
--print @job_name
--print @SQLInstance
--print @ComputerName
--print @SessionLoginName
--
--EXECUTE @RC = [master].[dba].[WMI_alert_ops_if_failover] 
--@starttime,
--@alert_text,
--@alert_state,
--@name,
--@SQLInstance,
--@ComputerName,
--@SessionLoginName
--
-- #################################################
-- SERVICE BROKER MUST BE ENABLED TO ALLOW THESE ALERTS TO WORK
-- #################################################
--
-- select name, is_broker_enabled from sys.databases
-- ALTER DATABASE rhythmyx SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;
--
-- Modification History
-- ====================
--
-- 25/02/2009			Haden Kingsland			To allow for NULL input parameter values and to change emails to HTML format
--
--#################################################################################################

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

(
    @starttime datetime,
	@alert_text nvarchar(1000),
	@state int,
	@name nvarchar(30),
	@SQLInstance nvarchar(25),
	@ComputerName nvarchar(20),
	@SessionLoginName nvarchar(25)
		
   -- @p_error_description				varchar(300) OUTPUT

  )

as

begin

declare   @mirrorrole tinyint,
			@dbname varchar(15),
			@database varchar(15),
			@alert_name varchar(256),
			@alert_status tinyint,
			@mirror_status tinyint,
			@MailProfileName VARCHAR(50),
			@mail_subject varchar(400),
			@mail_body varchar(400),
			@mail_body2 varchar(400),
			@mail_body3 varchar(400),
			@mail_body4 varchar(600),
			@mail_body5 varchar(600),
			@role varchar(15),
			@opposing_role varchar(15),
			@mirror_state_desc nvarchar(120),
			@witness_state_desc nvarchar(120),
			@mirror_partner nvarchar(256),
			@mirror_witness_name nvarchar(256),
			@mirror_witness_state tinyint,
			@mirror_state tinyint,
			@email_flag bit,
			@mirror_event varchar(70),
			@ERR_MESSAGE varchar(200),
			@ERR_NUM int,
			@NewLine CHAR(2),
			@Q CHAR(1),
			@tableHTML VARCHAR(MAX),
			@lineHTML VARCHAR(MAX),
			@TR varchar(20),
			@END	 varchar(30),
			@ENDTAB varchar(20);

-- ###########################
-- FOR DEBUG
-- ###########################
--
--  declare  @starttime datetime,
--@alert_text nvarchar(1000),
--@state int,
--@name nvarchar(30),
--@SQLInstance nvarchar(25),
--@ComputerName nvarchar(20),
--@SessionLoginName nvarchar(25);
--
-- ###########################

SET @newLine = CHAR(13) + CHAR(10) 
SET @Q = CHAR(39) 

-- initialize variables (otherwise concat fails because the variable value is NULL)
set @lineHTML = '' 
set @tableHTML = ''

SET @tableHTML =
		'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset// EN">' +
		'<html>' +
		'<LANG="EN">' +
		'<head>' +
		'<TITLE>Database Statistics</TITLE>' +
		'</head>' +
		'<body>' +
		'<font color="red" face="Comic Sans MS" >' + 
		'<CENTER>' + 
		'<H1>Database Mirroring State Change Notifications</H1>' +
		--'<H2>inc System Databases</H2>' +
		'<table border="1" width=100%>' +
		'<tr BGCOLOR="yellow">' + 
		-- list all table headers here
		'<th>Alert Information</th>' + '</tr>'

SET @TR = '</tr>'
SET @ENDTAB = '</font></table>'
SET @END = '</font></table></body></html>'

-- ###########################
-- FOR DEBUG
-- ###########################
--set @name = 'edm'
--set @state = 8
--set @mirrorrole = 0

--print 'database name = ' + @name
--print @alert_text

--select	m.mirroring_role,
--					m.mirroring_witness_state_desc,
--					m.mirroring_partner_instance,
--					m.mirroring_state,
--					m.mirroring_state_desc,
--					m.mirroring_witness_state,
--					m.mirroring_witness_name,
--					d.name  from 
--					sys.databases d, sys.database_mirroring m
--					where d.database_id = m.database_id
--					and d.name = @name
--					and m.mirroring_state_desc is NOT NULL
--
-- ###########################

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%Default%'

	IF @name IS NOT NULL  -- do nothing if no database name parameter is passed in.
	and @name <> ''
	BEGIN

		BEGIN TRY

			select	@mirrorrole = m.mirroring_role,
						@witness_state_desc = m.mirroring_witness_state_desc,
						@mirror_partner = m.mirroring_partner_instance,
						@mirror_state = m.mirroring_state,
						@mirror_state_desc = m.mirroring_state_desc,
						@mirror_witness_state = m.mirroring_witness_state,
						@mirror_witness_name= m.mirroring_witness_name,
						@database = d.name  from 
						sys.databases d, sys.database_mirroring m
						where d.database_id = m.database_id
						and d.name = @name
						and m.mirroring_state_desc is NOT NULL

	--select	m.mirroring_role,
	--					m.mirroring_witness_state_desc,
	--					m.mirroring_partner_instance,
	--					m.mirroring_state,
	--					m.mirroring_state_desc,
	--					m.mirroring_witness_state,
	--					m.mirroring_witness_name,
	--					d.name  from 
	--					sys.databases d, sys.database_mirroring m
	--					where d.database_id = m.database_id
	--					and d.name = 'edm'
	--					and m.mirroring_state_desc is NOT NULL

	--				5  = Connection with Principal Lost (for mirror server)
	--				6  = Connection with mirror lost
	--				7  = Manual failover
	--				8  = Automatic failover
	--				9  = Mirroring suspended
	--				10 = No Quorum (unable to connect to the witness server)
							
				print 'state = ' +  RTRIM(CONVERT(CHAR(10),@state))
									
				IF		(@state = 5 and @mirrorrole = 2) or				-- WMI connection with principal lost and role is mirror
						 (@state = 6 and @mirrorrole = 1)	and		-- WMI connection with mirror lost and role is principal
						@mirror_state = 1										-- disconnected from the other partner
					BEGIN
					
						IF @state = 5
							BEGIN
								set @mirror_event = 'Connection with Principal Lost (for mirror server)' 
								Set @role = 'MIRROR'
							END
						ELSE
							BEGIN
								IF @state = 6
									BEGIN
										set @mirror_event = 'Connection with mirror lost'
										Set @role = 'PRINCIPAL'
									END
							END
					
						SET @MAIL_BODY = 'The ' + @@SERVERNAME + '\' + upper(@database) + ' database has become disconnected from it''s partner instance at .... ' + @mirror_partner 
						SET @MAIL_BODY2 ='. The database role at this site for the ' + @@SERVERNAME + '\' + upper(@database) + ' database is currently .... ' + @role + '.'
						SET @MAIL_BODY3 =' The ' + UPPER(@database) + ' database is currently ' + @mirror_state_desc
						SET @MAIL_BODY4 ='. The WITNESS Server ' + @mirror_witness_name + ' is currently ' + @witness_state_desc + ' . Please check website functionality and investigate issues via Application Manager/Idera SQLDM/SQL Server tools'
						SET @MAIL_SUBJECT = 'IMPORTANT -- DATABASE MIRROR STATE CHANGE OF THE ' + @@SERVERNAME + '\' + upper(@database)	+ ' database -- PLEASE READ'
				
						SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3 + @MAIL_BODY4;
				
					END
					
				ELSE
					BEGIN
					
							IF	@state = 7 or	-- WMI manual failover
								@state = 8		-- WMI automatic failover
								BEGIN
									IF @state = 7 and @mirrorrole = 1
										BEGIN
											print 'state in here is = ' +  RTRIM(CONVERT(CHAR(10),@state))
											set @mirror_event = 'Manual failover' 
											Set @role = 'PRINCIPAL'
											set @opposing_role = 'MIRROR'
											print @mirror_event
										END
									ELSE
										BEGIN
											IF @state = 7 and @mirrorrole = 2
												BEGIN
													set @mirror_event = 'Manual failover' 
													set @role = 'MIRROR'
													set @opposing_role = 'PRINCIPAL'
												END	
											ELSE
												BEGIN
													IF @state = 8 and @mirrorrole = 1
														BEGIN
															set @mirror_event = 'Automatic failover' 
															Set @role = 'PRINCIPAL'
															set @opposing_role = 'MIRROR'
														END
													ELSE
														BEGIN
															IF @state = 8 and @mirrorrole = 2
																BEGIN
																	set @mirror_event = 'Automatic failover' 
																	set @role = 'MIRROR'
																	set @opposing_role = 'PRINCIPAL'
																END
														END
												END
										END			

										SET @MAIL_BODY =  ISNULL(@mirror_event,'''An Unknown Mirroring Event''') + ' has occurred on the mirrored ' + @database + ' database on the ' + @@SERVERNAME  + ' instance.... '
										SET @MAIL_BODY2 ='The ' + ISNULL(@name,@database) + ' database is now running as the ' +  ISNULL(@opposing_role,'''UNKNOWN ROLE''') + ' under the ' + @mirror_partner + ' instance. The database role at site... ' + @@SERVERNAME + ' is now ' + @role + '.'
										SET @MAIL_BODY3 =' The ' + ISNULL(@name,@database) + ' database is currently ... ' + @mirror_state_desc + '.'
										SET @MAIL_BODY4 =' The WITNESS Server ' + @mirror_witness_name + ' is currently ... ' + @witness_state_desc  + ' . Please check website functionality and investigate issues via Application Manager/Idera SQLDM/SQL Server tools'
										SET @MAIL_SUBJECT = 'IMPORTANT -- DATABASE MIRROR STATE CHANGE OF THE ' + @@SERVERNAME + '\' + upper(@database)	+ ' database -- PLEASE READ'					
										
										SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3 + @MAIL_BODY4;
										
										-- ###########################
										-- FOR DEBUG
										-- ###########################
										--
										--print 'mail body is ... ' + @MAIL_BODY 
										--print  'mail body2 is ... ' + @MAIL_BODY2
										--print 'name ' + @name
										--print 'partner ' + @mirror_partner
										--print 'desc ' + @mirror_state_desc
										--print 'role ' + @role
										--print 'witness ' + @mirror_witness_name
										--print 'witness state ' + @witness_state_desc
										--print 'DB Name ' + @name 
										--
										-- ###########################
								
								END
							ELSE
								BEGIN
									IF	@state = 9 and	     -- WMI mirroring suspended
										@mirror_state = 0		-- mirroring is suspended
										BEGIN
											set @mirror_event = 'Mirroring suspended' 
											SET @MAIL_BODY = ISNULL(@mirror_event,'''An Unknown Mirroring Event''') + ' has occurred on the mirrored ' + @database + ' database on the ' + @@SERVERNAME  + ' instance.... '
											SET @MAIL_BODY2 = 'Mirroring has become SUSPENDED between the ' + upper(@database) + ' database on the ' + @@SERVERNAME + ' instance ' 
											SET @MAIL_BODY3 ='and the ' + upper(@database) + ' database on the ' + @mirror_partner + ' instance. Please investigate using Application Manager/Idera SQLDM/SQL Server Tools and check associated database status.'
											SET @MAIL_SUBJECT = 'IMPORTANT -- DATABASE MIRROR STATE CHANGE OF THE ' + @@SERVERNAME + '\' + upper(@database)	+ ' database -- PLEASE READ'
											--SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3;

										END
									ELSE
										BEGIN
											IF	@state = 10 and				-- WMI unable to connect to witness server
												@mirror_witness_state = 0	-- witness disconnected
												BEGIN
													set @mirror_event = 'No Quorum (unable to connect to the witness server)'
													SET @MAIL_BODY	= ISNULL(@mirror_event,'''An Unknown Mirroring Event''') + ' has occurred on the mirrored ' + @database + ' database on the ' + @@SERVERNAME  + ' instance.... '
													SET @MAIL_BODY2 = 'The WITNESS SERVER ... ' + @mirror_witness_name + ' is disconnected from the ' + @@SERVERNAME + ' instance ' 
													SET @MAIL_BODY3 ='and the ' + @mirror_partner + ' instance. Please investigate using Application Manager/Idera SQLDM/SQL Server Tools and check associated database status.'					
													SET @MAIL_SUBJECT = 'IMPORTANT -- DATABASE MIRROR STATE CHANGE OF THE ' + upper(@mirror_witness_name)	+ ' Witness server -- PLEASE READ'
													--SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3;
												END
										END
										
										SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3;
								END				
					END		

					set @linehtml = @lineHTML + '<tr>' + '<td>' + '<font color="White" face="Comic Sans MS" >' + @MAIL_BODY5 + '</font>' + '</tr>' + '</td>'

				-- build up HTML statement

				set @tableHTML = @tableHTML + @lineHTML + @END

				-- as the <td> tags are auto-generated, I need to replace then with a new <td>
				-- tag including all the required formatting.

				set @tableHTML = REPLACE( @tableHTML, '<td>', '<td BGCOLOR="orange">' );

				print @tableHTML

-- ####################################################							
-- for HTML emails as cannot send this type using msdb.dbo.sp_notify_operator 
-- ####################################################

				EXEC msdb.dbo.sp_send_dbmail
				@profile_name = @MailProfileName,
				@recipients = 'haden.kingsland@poferries.com',
				--@recipients = 'haden.kingsland@poferries.com',
				@body_format = 'HTML',
				@body = @tableHTML,
				@subject = @mail_subject

-- ###############							
-- for non-HTML emails
-- ###############	
								
				--EXEC msdb.dbo.sp_notify_operator 
				--@profile_name = @MailProfileName, 
				--@name=N'Haden Kingsland',
				--@subject =  @mail_subject, 
				--@body= @mail_body5		

		END TRY
		
		BEGIN CATCH
		
				-- Have to re-initialize these here again to be able to use then in the CATCH block
				-- initialize variables (otherwise concat fails because the variable value is NULL)
				set @lineHTML = '' 
				set @tableHTML = ''

				SET @tableHTML =
					'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset// EN">' +
					'<html>' +
					'<LANG="EN">' +
					'<head>' +
					'<TITLE>Database Statistics</TITLE>' +
					'</head>' +
					'<body>' +
					'<font color="Blue" face="Comic Sans MS" >' + 
					'<CENTER>' + 
				'<H1>Database Mirroring Alert Notification Failure</H1>' +
				--'<H2>inc System Databases</H2>' +
				'<table border="1" width=100%>' +
				'<tr BGCOLOR="yellow">' + 
					-- list all table headers here
					'<th>Alert Information</th>' + '</tr>'

				SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
				
				SET @MAIL_BODY='Error whilst running WMI_Alert_Ops_if_failover for database .... ' + @database+ '. Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ... ' + @ERR_MESSAGE + @NewLine
				SET @MAIL_BODY2= 'Mirroring event was ..... ' + ISNULL(@mirror_event,'''UNKNOWN''') +  ' for the .... ' + @database + ' database within the original instance ....' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(20)))) + '.' + @NewLine
				SET @MAIL_BODY3='Go to the Idera SQLDM link to monitor the ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(20)))) + ' instance .... http://chssqlmon/SQLdm/default.aspx'
				SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3
				SET @MAIL_SUBJECT ='Error whilst running WMI_Alert_Ops_if_failover for database .... ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(20)))) + '\' + @database
	
				set @linehtml = @lineHTML + '<tr>' + '<td>' + '<font color="White" face="Comic Sans MS" >' + @MAIL_BODY5 + '</font>' + '</tr>' + '</td>'
	
				---- build up HTML statement

				set @tableHTML = @tableHTML + @lineHTML + @END

				---- as the <td> tags are auto-generated, I need to replace then with a new <td>
				---- tag including all the required formatting.

				set @tableHTML = REPLACE( @tableHTML, '<td>', '<td BGCOLOR="red">' );
	
-- ####################################################							
-- for HTML emails as cannot send this type using msdb.dbo.sp_notify_operator 
-- ####################################################

				EXEC msdb.dbo.sp_send_dbmail
				@profile_name = @MailProfileName,
				@recipients = 'haden.kingsland@poferries.com',
				--@recipients = 'haden.kingsland@poferries.com',
				@body_format = 'HTML',
				@body = @tableHTML,
				@subject = @mail_subject

-- ###############							
-- for non-HTML emails
-- ###############	
			
				--EXEC msdb.dbo.sp_notify_operator 
				--@profile_name = @MailProfileName, 
				--@name=N'Haden Kingsland',
				--@subject =  @mail_subject, 
				--@body= @mail_body5			
		
		END CATCH
		
	END
	
END

