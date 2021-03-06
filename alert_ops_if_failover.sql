USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[alert_ops_if_failover]    Script Date: 06/09/2018 13:30:01 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[alert_ops_if_failover]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 31/10/2006
-- Version	: 01:00
--
-- Desc		: To email selected operators when a database fails over.
--			  To be run in conjuction with the Alert Ops if Failover "DB NAME"
--			  Agent Alert.
--			  It is triggered by the following WMI events ...
--			  SELECT state FROM DATABASE_MIRRORING_STATE_CHANGE 
--			  WHERE DatabaseName =  'database name' and state = integer
--			  States we are interested in are as follows:
--				
--            6  = Connection with mirror lost
--			  7  = Manual failover
--            8  = Automatic failover
--			  9  = Mirroring suspended
--	          10 = No Quorum (unable to connect to the witness server)
--
-- Modification History
-- ====================
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

as

begin

declare @mirrorrole tinyint
declare @dbname varchar(15)
declare @database varchar(15)
declare @alert_name varchar(256)
declare @alert_status tinyint
declare @mirror_status tinyint
DECLARE @MailProfileName VARCHAR(50)
declare @mail_subject varchar(250)
declare @mail_body varchar(250)
declare @mail_body2 varchar(250)
declare @mail_body3 varchar(250)
declare @mail_body4 varchar(250)
declare @mail_body5 varchar(400)
declare @role varchar(15)
--declare @mirror_state nvarchar(120)
declare @mirror_state_desc nvarchar(120)
declare @witness_state_desc nvarchar(120)
declare @mirror_partner nvarchar(256)
declare @mirror_witness_name nvarchar(256)
declare @mirror_witness_state tinyint
declare @mirror_state tinyint
declare @email_flag tinyint


SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA-Alerts%'

SET @EMAIL_FLAG = 0

DECLARE database_mirror_state CURSOR FOR

	select m.mirroring_role,
	m.mirroring_witness_state_desc,
	m.mirroring_partner_instance,
	m.mirroring_state,
	m.mirroring_state_desc,
	m.mirroring_witness_state,
	m.mirroring_witness_name,
	d.name  from 
	sys.databases d, sys.database_mirroring m
	where d.database_id = m.database_id
	and m.mirroring_state_desc is NOT NULL

-- Open the cursor.
	OPEN database_mirror_state;

-- Loop through the cursor.

	FETCH NEXT
		FROM database_mirror_state
		INTO @mirrorrole,
		@witness_state_desc,
		@mirror_partner,
		@mirror_state,
		@mirror_state_desc,
		@mirror_witness_state,
		@mirror_witness_name,
		@database

		WHILE @@FETCH_STATUS = 0
		BEGIN

			If @mirrorrole = 1  -- principal 

				BEGIN
				Set @role = 'PRINCIPAL'
				SET @MAIL_BODY = 'The ' + @database + ' database has failed over from the ' + @mirror_partner + ' instance. '
				SET @MAIL_BODY2 =' The database role is now ' + @role
				SET @MAIL_BODY3 =' The ' + @database + ' is currently ' + @mirror_state_desc
				SET @MAIL_BODY4 ='The WITNESS Server ' + @mirror_witness_name + ' is currently ' + @witness_state_desc
				SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3 + @MAIL_BODY4
				END
			
			Else 
			
			If @mirrorrole = 2  -- mirror
			
				BEGIN
					Set @role = 'MIRROR'
					SET @MAIL_BODY = 'The ' + @database + ' database has failed over to the ' + @mirror_partner + ' instance ' 
					SET @MAIL_BODY2 ='.  The database role at ' + @@SERVERNAME + ' is now ' + @role
					SET @MAIL_BODY3 =' . The ' + @database + ' database state is currently ' + @mirror_state_desc
					SET @MAIL_BODY4 =' . The state of the WITNESS Server ' + @mirror_witness_name + ' is currently ' + @witness_state_desc
					SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2 + @MAIL_BODY3 + @MAIL_BODY4

					SET @MAIL_SUBJECT = 'Database FAILOVER of ' + @@SERVERNAME + '\' + upper(@database) + ' to the mirror site ...' + @mirror_partner

					EXEC msdb.dbo.sp_notify_operator 
					@profile_name = @MailProfileName, 
					@name=N'DBA-Alerts',
					@subject =  @mail_subject, 
					@body= @mail_body5

				END

			If @mirror_witness_state = 0 -- witness disconnected
			BEGIN

				SET @MAIL_BODY = 'The ' + @mirror_witness_name + ' is disconnected from the ' + @@SERVERNAME + ' instance ' 
				SET @MAIL_BODY2 ='and the ' + @mirror_partner + ' instance. Please investigate and check associated database status.'
				SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2
				SET @MAIL_SUBJECT = 'The Witness server ' + upper(@mirror_witness_name) + 'is disconnected.'
					
				EXEC msdb.dbo.sp_notify_operator 
				@profile_name = @MailProfileName, 
				@name=N'DBA-Alerts',
				@subject =  @mail_subject, 
				@body= @mail_body5

			END


			If @mirror_state = 0 -- mirroring is suspended
			BEGIN

				SET @MAIL_BODY = 'Mirroring has become SUSPENDED for the ' + upper(@database) + 'database on the ' + @@SERVERNAME + ' instance ' 
				SET @MAIL_BODY2 ='and the ' + @mirror_partner + ' instance. Please investigate and check associated database status.'
				SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2
				SET @MAIL_SUBJECT = 'Mirroring is suspended for ' + @@SERVERNAME + '\' + upper(@database)
	
				EXEC msdb.dbo.sp_notify_operator 
				@profile_name = @MailProfileName, 
				@name=N'DBA-Alerts',
				@subject =  @mail_subject, 
				@body= @mail_body5

				print @mail_body5
	
			END

			Else

			If @mirror_state = 1 -- disconnected from the other partner
				BEGIN

				SET @MAIL_BODY = 'Database ' + @@SERVERNAME + '\' + upper(@database) + 'has become disconnected from' 
				SET @MAIL_BODY2 =' the partner ' + @mirror_partner + ' instance. Please investigate and check associated database status.'
				SET @MAIL_BODY5 = @MAIL_BODY + @MAIL_BODY2
				SET @MAIL_SUBJECT = @@SERVERNAME + '\' + upper(@database) + ' is disconnected from ' + @mirror_partner
	
				EXEC msdb.dbo.sp_notify_operator 
				@profile_name = @MailProfileName, 
				@name=N'DBA-Alerts',
				@subject =  @mail_subject, 
				@body= @mail_body5		

			END

			FETCH NEXT
				FROM database_mirror_state
				INTO @mirrorrole,
				@witness_state_desc,
				@mirror_partner,
				@mirror_state,
				@mirror_state_desc,
				@mirror_witness_state,
				@mirror_witness_name,
				@database
			
		END

-- Close and deallocate the cursor.
		CLOSE database_mirror_state
		DEALLOCATE database_mirror_state

END;

