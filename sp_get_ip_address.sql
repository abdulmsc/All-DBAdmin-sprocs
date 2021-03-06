USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[sp_get_ip_address]    Script Date: 07/09/2018 10:06:47 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 31/10/2013
-- Version	: 01:00
--
-- Desc		: To retrun IP address of a server
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
--
ALTER Procedure [dba].[sp_get_ip_address] (@ip varchar(40) out)
as

begin

Declare @ipLine varchar(200),
		@pos int,
		@XPCMDSH_ORIG_ON varchar(1)
  
--------------------------------------------------------------------------------------------------------------------
-- Check whether xp_cmdshell is turned off via Surface Area Configuration (2005) / Instance Facets (2008)
-- This is best practice !!!!! If it is already turned on, LEAVE it on !!

-- turn on advanced options
	EXEC sp_configure 'show advanced options', 1 reconfigure 
	RECONFIGURE  

	CREATE TABLE #advance_opt (name VARCHAR(20),min int, max int, conf int, run int)
			INSERT #advance_opt
		EXEC sp_configure 'xp_cmdshell' -- this will show whether it is turned on or not
				
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
  
          set @ip = NULL
          Create table #temp (ipLine varchar(200))
          Insert #temp exec xp_cmdshell 'ipconfig'
          select @ipLine = ipLine
          from #temp
          where upper (ipLine) like '%IP%4%ADDRESS%'
          if (isnull (@ipLine,'***') != '***')
          begin 
                set @pos = CharIndex (':',@ipLine,1);
                set @ip = rtrim(ltrim(substring (@ipLine , 
               @pos + 1 ,
                len (@ipLine) - @pos)))
           end 
           
		drop table #temp

-----------------------------------------------------------------------------------------------------------------------		
-- turn off advanced options

	IF @XPCMDSH_ORIG_ON = 'N'  -- if xp_cmdshell was NOT originally turned on, then turn it off 
	BEGIN

		--  turn off xp_cmdshell to dis-allow operating system commands to be run
		EXEC sp_configure 'xp_cmdshell', 0  reconfigure
		RECONFIGURE

		EXEC sp_configure 'show advanced options', 0 reconfigure
		RECONFIGURE
		
		 
	END
-----------------------------------------------------------------------------------------------------------------------
end

