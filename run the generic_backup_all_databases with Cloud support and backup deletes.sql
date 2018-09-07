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

declare			@RC int
declare	 		@job_name varchar(128)
declare			@BACKUP_LOCATION varchar(200)
declare			@backup_type VARCHAR(1)
declare			@dbname nvarchar(2000)
declare			@iscloud varchar(1)
declare			@copy varchar(1)
declare			@freq varchar(10)
declare  			@production varchar(1)
declare 			@INCSIMPLE	varchar(1) 
declare 			@ignoredb varchar(1)
declare 			@checksum varchar(1)
declare 			@isSP varchar(1)
declare			@recipient_list	varchar(2000)
declare			@format	varchar(8) = 'FORMAT' -- noformat or format
declare			@init varchar(6) = 'INIT' -- noinit or init
declare			@operator varchar(30) -- for LOR this should be... DBA-Alerts
declare			@cred varchar(30) = NULL
declare			@mailprof varchar(30) -- DBA-Alerts
declare			@encrypted	bit = 0 -- (0,1) default of 0 for no encryption required 
declare			@algorithm	varchar(20) = NULL -- defaults to NULL / Valid options are... AES_128 | AES_192 | AES_256 | TRIPLE_DES_3KEY
declare			@servercert	varchar(30) = NULL -- defaults to NULL
declare			@retaindays	int
declare			@buffercount int = 30 -- can be set to any number within reason
declare			@deletion_param int = 1 --can be any integer to allow deletion (i.e -- number of weeks or days back to delete backups) -- Default is 1
declare			@deletion_type bit = 0 -- 0 = weeks, 1 = days -- MUST be set to define value by which old backup files are deleted -- Default is weeks
 
select 			@job_name = 'Database Backups'
select 			@backup_location = 'E:\SQL 2008R2\SQLBACK\' --'\\darfas01\cifs_sqlbak_sata11$\DAREPMSQL01\EPM_LIVE\SQLTRN\' --
select 			@backup_type = 'S' -- 'F', 'S', 'D', 'T'
select 			@dbname ='' --  a valid database name or spaces
select			@iscloud = 'N' -- if yes, then you MUST uncommment the @cred variable and pass in a valid Azure credential
select 			@copy = 0 -- 1 or 0 -- copy only backup or not -- 0 is for not copy only
select 			@checksum = 1 -- 1 or 0 -- create a checksum for backup integrity validation
select 			@freq = 'Daily' -- 'Weekly', 'Daily'
select 			@production = 'Y' -- 'Y', 'N' -- only use 'N' for non production instances
select 			@INCSIMPLE = 'Y' -- 'Y', 'N' -- include SIMPLE recovery model databases
select 			@ignoredb = 'N' -- 'Y' or 'N' -- if "Y" then it will ignore the databases in the @dbname parameter
select			@isSP = 'N' -- 'Y' or 'N' -- set to Y if the instance is used for SharePoint. Implemented due to extra long SP database names!
select			@recipient_list = 'haden.kingsland@cii.co.uk;'
select			@operator = 'DBA-Alerts'
-- uncommment the @cred variable and pass in a valid Azure credential if you required BLOB storage Azure backups
--select			@cred = '<your credential here>' -- uncomment this line if you need to use the iscloud option and enter your Azure BLOB storage credential
select			@mailprof = 'DBA-Alerts'
select			@encrypted = 0 -- default is 0 for not required
-- uncomment and set the below only if you require encrypted backups
--select			@algorithm = NULL -- defaults to NULL / Valid options are... AES_128 | AES_192 | AES_256 | TRIPLE_DES_3KEY
--select			@servercert	= NULL -- a valid server certificate from sys.certificates for the backups
select			@retaindays = 37
select			@buffercount = 50
select			@deletion_param = 1 -- can be any integer to allow deletion (i.e -- number of weeks or days back to delete backups) -- Default is 1
select			@deletion_type	= 1 -- 0 = weeks, 1 = days -- MUST be set to define value by which old backup files are deleted -- Default is weeks

--
-- Please note that the parameters MUST be in the correct order or the procedure WILL give incorrect results!
--
 EXECUTE @RC = [dbadmin].[dba].[usp_generic_backup_all_databases] 
 @job_name,
 @backup_location,
 @backup_type,
 @dbname,
 @iscloud,
 @copy,
 @freq,
 @production,
 @INCSIMPLE,
 @ignoredb,
 @checksum,
 @isSP,
 @recipient_list,
 @format,
 @init,
 @operator,
 @cred,
 @mailprof,
 @encrypted,
 @algorithm,
 @servercert,
 @retaindays,
 @buffercount,
 @deletion_param,
 @deletion_type