USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_change_db_owner_to_sa]    Script Date: 07/09/2018 10:08:38 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--#######################################################################################################
--
-- Date			: 18/01/2017
-- DBA			: Haden Kingsland (@theflyingdba)
-- Description	: To create a database for new deployments and allow for parameterised decisions for 
--				  database deployment.	
--
--	Name:       usp_generic_create_database
-- 
-- Acknowledgements:
--------------------
--
--#######################################################################################################
-- Usage...
--#########
-- exec dbadmin.dba.usp_change_db_owner_to_sa '<your database name here>'
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
ALTER procedure [dba].[usp_change_db_owner_to_sa]
@databasename varchar(400)
as

DECLARE @query as varchar(max),
		@sql varchar(max);

begin

	SET @SQL = N'USE ' + QUOTENAME(@databasename);
	set @query = 'EXEC ' + '[' + @databasename + ']' + '.dbo.sp_changedbowner @loginame = N''sa'', @map = false'
	EXECUTE(@SQL);
	exec(@query);

end


