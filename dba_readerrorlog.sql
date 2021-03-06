USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[dba_readerrorlog]    Script Date: 07/09/2018 09:23:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 31/10/2006
-- Version	: 01:00
--
-- Desc		: To read the SQL Server error logs with passed in
--			  parameters.
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


ALTER PROC [dba].[dba_readerrorlog]( 
   @p1     INT = 0, 
   @p2     INT = NULL, 
   @p3     VARCHAR(255) = NULL, 
   @p4     VARCHAR(255) = NULL) 
AS 
BEGIN 

   IF (NOT IS_SRVROLEMEMBER(N'securityadmin') = 1) 
   BEGIN 
      RAISERROR(15003,-1,-1, N'securityadmin') 
      RETURN (1) 
   END 
    
   IF (@p2 IS NULL) 
       EXEC sys.xp_readerrorlog @p1 
   ELSE 
       EXEC sys.xp_readerrorlog @p1,@p2,@p3,@p4 
END

