USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_generic_create_database]    Script Date: 07/09/2018 10:13:45 ******/
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
-- Usage...
--#########

--DECLARE @databasename varchar(400),
--@filepath varchar(400),
--@logpath varchar(400),
--@recoverymodel varchar(11) = NULL,
--@datamaxsize int = NULL,
--@logmaxsize int = NULL,
--@filegrowth int = NULL,
--@collation varchar(100),
--@initdatasize int = NULL,
--@initlogsize int = NULL,
--@containment varchar(7),
--@RC int;

--select @databasename = 'Hadentest' -- change this to suit your needs
--select @filepath = 'F:\SQLDATA\Data\' -- change this to suit your needs
--select @logpath =  'E:\SQLLOGS\Logs\' -- change this to suit your needs
--select @recoverymodel = 'SIMPLE' -- can be FULL, SIMPLE or NULL (will then default to SIMPLE)
--select @datamaxsize = NULL -- default to 8192 if NULL
--select @logmaxsize = NULL -- size is dependant on recovery model. If FULL mode, then will be 30% of the combined max size of both main data files
--select @filegrowth = NULL -- default to 64MB if left as NULL
--select @collation = 'DEFAULT' -- If DEFAULT then Latin1_General_CI_AS, else it takes the default collation from the server
--select @initdatasize = NULL -- 4096  -- if NULL then will default to an initial data file size of 2GB per file
--select @initlogsize = NULL -- 2048  -- if NULL then will default to an initial log file size of 1GB
--select @containment = 'DEFAULT' -- if DEFAULT, and SQL Version 2012 or higher, containment will be NONE. Values should be DEFAULT or PARTIAL.

---- please read this article... --https://technet.microsoft.com/en-us/library/hh534404.aspx -- before creating a contained database!

--EXECUTE @RC = DBAdmin.dba.usp_generic_create_database
--@databasename,
--@filepath,
--@logpath,
--@recoverymodel,
--@datamaxsize,
--@logmaxsize,
--@filegrowth,
--@collation,
--@initdatasize,
--@initlogsize,
--@containment

ALTER procedure [dba].[usp_generic_create_database]
-- input parameters...
@databasename varchar(400),
@filepath varchar(400),
@logpath varchar(400),
@recoverymodel varchar(11) = NULL,
@datamaxsize int = NULL,
@logmaxsize int = NULL,
@filegrowth int = NULL,
@collation varchar(100),
@initdatasize int = NULL, 
@initlogsize int = NULL,
@containment varchar(7)

as
DECLARE @comp varchar(3),
		@query as varchar(max),
		@master sysname,
		@sql varchar(max),
		@create varchar(500);

BEGIN

	-- default recovery model to SIMPLE is not supplied
	If @recoverymodel = '' 
	or @recoverymodel is NULL
		BEGIN
			Set @recoverymodel = 'SIMPLE'
		END;

	IF @datamaxsize is NULL
		BEGIN
			Set @datamaxsize = 8192 -- set to 4GB by default if none supplied
		END

	IF @logmaxsize is NULL
	BEGIN
		IF @recoverymodel = 'SIMPLE'
			BEGIN
				Set @logmaxsize = 2048 -- 2GB
			END
			ELSE
				BEGIN
					set @logmaxsize = ((@datamaxsize * 2) * 0.30) -- 30% of max datafile size as a default for the FULL recovery model
				END
	END;
	
	IF @filegrowth is NULL
		BEGIN
			set @filegrowth = 64 -- default to 64MB
		END
	
	If @collation = 'DEFAULT'
		BEGIN
			set @collation = 'Latin1_General_CI_AS'
		END
		ELSE
			BEGIN
				select @collation = convert (sysname, serverproperty(N'collation')) 
			END

	
	If @initdatasize is NULL
		BEGIN
			set @initdatasize = 2048 -- if not set then will default to an initial data file size of 2GB per file
		END

	If @initlogsize is NULL
		BEGIN
			set @initlogsize = 1024 -- if not set then will default to an initial log file size of 1GB
		END

	set @master = 'master'
	SET @SQL = N'USE ' + QUOTENAME(@master);
	SET @query = ''
	SELECT @comp = CASE WHEN @@VERSION LIKE '%9.0%'	THEN 90 --'SQL 2005' 
					   --WHEN @@VERSION LIKE '%8.0.%'	THEN 'SQL 2000'
					   WHEN @@VERSION LIKE '%10.0%' THEN 100 -- 'SQL 2008' 
					   WHEN @@VERSION LIKE '%10.5%' THEN 100 -- 'SQL 2008 R2' 
					   WHEN @@VERSION LIKE '%11.0%' THEN 110 --'SQL 2012'
					   WHEN @@VERSION LIKE '%12.0%' THEN 120 --'SQL 2014' 
					   WHEN @@VERSION LIKE '%13.0%' THEN 130 --'SQL 2016'
					   WHEN @@VERSION LIKE '%14.0%' THEN 140 --'SQL 2016'
	END;

	If @comp in ('110','120','130','140')
	BEGIN
		IF @containment = 'DEFAULT'
		BEGIN
			set @create = 'CREATE DATABASE [' + @databasename + '] CONTAINMENT = NONE'
		END
			ELSE
				BEGIN
					set @create = 'CREATE DATABASE [' + @databasename + '] CONTAINMENT = PARTIAL'
				END

		SELECT @query = @create +  --'CREATE DATABASE [' + @databasename + ']  
				' ON  PRIMARY
				( NAME = N'''  + @databasename + ''',  FILENAME = N''' + @filepath + '' + @databasename  +'.mdf'' ,  SIZE = 256MB , MAXSIZE = 2048MB, FILEGROWTH = 64MB ),
				FILEGROUP [DATA]  DEFAULT 
				( NAME = N''' + @databasename +  '_data_1'', FILENAME = N''' + @filepath + '' + @databasename + '_data_1.ndf'' , SIZE = ' + convert(varchar(6),@initdatasize) + 'MB , MAXSIZE = ' + convert(varchar(6),@datamaxsize) + 'MB , FILEGROWTH = ' + convert(varchar(3),@filegrowth) + 'MB ),
				( NAME = N''' + @databasename  + '_data_2'', FILENAME = N''' + @filepath + '' + @databasename + '_data_2.ndf'' , SIZE = ' + convert(varchar(6),@initdatasize) + 'MB , MAXSIZE = ' + convert(varchar(6),@datamaxsize) + 'MB , FILEGROWTH = ' + convert(varchar(3),@filegrowth) + 'MB )
			LOG ON 
				( NAME = N''' + @databasename + '_log''' +', FILENAME = N''' + @logpath + '' + @databasename + '_log' +'.ldf'' , SIZE = ' + convert(varchar(6),@initlogsize) + 'MB , MAXSIZE = ' + convert(varchar(6),@logmaxsize) + 'MB , FILEGROWTH = ' + convert(varchar(3),@filegrowth) + 'MB )
		COLLATE ' + @collation + '
		ALTER DATABASE ' + @databasename  + ' SET COMPATIBILITY_LEVEL =' + @comp + ';

		IF (1 = FULLTEXTSERVICEPROPERTY(''IsFullTextInstalled''))
		begin
		EXEC ['+ @databasename +'].[dbo].[sp_fulltext_database] @action = ''enable''
		end;

		If ' + @comp + ' in (''120'',''130'',''140'')
		BEGIN
		ALTER DATABASE [' + @databasename + '] SET AUTO_CREATE_STATISTICS ON(INCREMENTAL = OFF)
		ALTER DATABASE [' + @databasename + '] SET DELAYED_DURABILITY = DISABLED
		END
		ELSE	
			BEGIN
					ALTER DATABASE ['+ @databasename + '] SET AUTO_CREATE_STATISTICS ON ;
			END

		-- can only be set at instance level prior to SQL 2012
		If ' + @comp + ' in (''110'',''120'',''130'',''140'')
		BEGIN
			ALTER DATABASE [' + @databasename + '] SET TARGET_RECOVERY_TIME = 0 SECONDS 
		END

		ALTER DATABASE ['+ @databasename + '] SET ANSI_NULL_DEFAULT OFF ;
		ALTER DATABASE ['+ @databasename + '] SET ANSI_NULLS OFF ;
		ALTER DATABASE ['+ @databasename + '] SET ANSI_PADDING OFF ;
		ALTER DATABASE ['+ @databasename + '] SET ANSI_WARNINGS OFF ;
		ALTER DATABASE ['+ @databasename + '] SET ARITHABORT OFF ;
		ALTER DATABASE ['+ @databasename + '] SET AUTO_CLOSE OFF ;
		ALTER DATABASE ['+ @databasename + '] SET AUTO_SHRINK OFF ;
		ALTER DATABASE ['+ @databasename + '] SET AUTO_UPDATE_STATISTICS ON ;
		ALTER DATABASE ['+ @databasename + '] SET CURSOR_CLOSE_ON_COMMIT OFF ;
		ALTER DATABASE ['+ @databasename + '] SET CURSOR_DEFAULT  GLOBAL ;
		ALTER DATABASE ['+ @databasename + '] SET CONCAT_NULL_YIELDS_NULL OFF ;
		ALTER DATABASE ['+ @databasename + '] SET NUMERIC_ROUNDABORT OFF ;
		ALTER DATABASE ['+ @databasename + '] SET QUOTED_IDENTIFIER OFF ;
		ALTER DATABASE ['+ @databasename + '] SET RECURSIVE_TRIGGERS OFF ;
		ALTER DATABASE ['+ @databasename + '] SET  ENABLE_BROKER ;
		ALTER DATABASE ['+ @databasename + '] SET AUTO_UPDATE_STATISTICS_ASYNC ON;
		ALTER DATABASE ['+ @databasename + '] SET DATE_CORRELATION_OPTIMIZATION OFF ;
		ALTER DATABASE ['+ @databasename + '] SET TRUSTWORTHY OFF ;
		ALTER DATABASE ['+ @databasename + '] SET ALLOW_SNAPSHOT_ISOLATION OFF ;
		ALTER DATABASE ['+ @databasename + '] SET PARAMETERIZATION SIMPLE ;
		ALTER DATABASE ['+ @databasename + '] SET READ_COMMITTED_SNAPSHOT OFF ;
		ALTER DATABASE ['+ @databasename + '] SET HONOR_BROKER_PRIORITY OFF ;
		ALTER DATABASE ['+ @databasename + '] SET RECOVERY ' + @recoverymodel + ';
		ALTER DATABASE ['+ @databasename + '] SET  MULTI_USER ;
		ALTER DATABASE ['+ @databasename + '] SET PAGE_VERIFY CHECKSUM  ;
		ALTER DATABASE ['+ @databasename + '] SET DB_CHAINING OFF ;'
	
	END
		ELSE IF @comp in ('100','90')
			BEGIN
				set @create = 'CREATE DATABASE [' + @databasename + ']'

				SELECT @query = @create +  --'CREATE DATABASE [' + @databasename + ']  
				' ON  PRIMARY
				( NAME = N''' + @databasename + ''',  FILENAME = N''' + @filepath + '' + '[' + @databasename + ']' +'.mdf'' ,  SIZE = 256MB , MAXSIZE = 2048MB, FILEGROWTH = 64MB ),
				FILEGROUP [DATA]  DEFAULT 
				( NAME = N''' + @databasename + '_data_1'', FILENAME = N''' + @filepath + '' + @databasename + '_data_1.ndf'' , SIZE = ' + convert(varchar(6),@initdatasize) + 'MB , MAXSIZE = ' + convert(varchar(6),@datamaxsize) + 'MB , FILEGROWTH = ' + convert(varchar(3),@filegrowth) + 'MB ),
				( NAME = N''' + @databasename + '_data_2'', FILENAME = N''' + @filepath + '' + @databasename + '_data_2.ndf'' , SIZE = ' + convert(varchar(6),@initdatasize) + 'MB , MAXSIZE = ' + convert(varchar(6),@datamaxsize) + 'MB , FILEGROWTH = ' + convert(varchar(3),@filegrowth) + 'MB )
					LOG ON 
				( NAME = N''' + @databasename + '_log''' +', FILENAME = N''' + @logpath + ''  + @databasename  + '_log' +'.ldf'' , SIZE = ' + convert(varchar(6),@initlogsize) + 'MB , MAXSIZE = ' + convert(varchar(6),@logmaxsize) + 'MB , FILEGROWTH = ' + convert(varchar(3),@filegrowth) + 'MB )
				COLLATE ' + @collation + '
				ALTER DATABASE '+ '[' + @databasename + ']' + ' SET COMPATIBILITY_LEVEL =' + @comp + ';


				IF (1 = FULLTEXTSERVICEPROPERTY(''IsFullTextInstalled''))
				begin
				EXEC ['+ @databasename +'].[dbo].[sp_fulltext_database] @action = ''enable''
				end;
	
				ALTER DATABASE ['+ @databasename + '] SET ANSI_NULL_DEFAULT OFF ;
				ALTER DATABASE ['+ @databasename + '] SET ANSI_NULLS OFF ;
				ALTER DATABASE ['+ @databasename + '] SET ANSI_PADDING OFF ;
				ALTER DATABASE ['+ @databasename + '] SET ANSI_WARNINGS OFF ;
				ALTER DATABASE ['+ @databasename + '] SET ARITHABORT OFF ;
				ALTER DATABASE ['+ @databasename + '] SET AUTO_CLOSE OFF ;
				ALTER DATABASE ['+ @databasename + '] SET AUTO_SHRINK OFF ;
				ALTER DATABASE [' + @databasename + '] SET AUTO_CREATE_STATISTICS ON ;
				ALTER DATABASE ['+ @databasename + '] SET AUTO_UPDATE_STATISTICS ON ;
				ALTER DATABASE ['+ @databasename + '] SET CURSOR_CLOSE_ON_COMMIT OFF ;
				ALTER DATABASE ['+ @databasename + '] SET CURSOR_DEFAULT  GLOBAL ;
				ALTER DATABASE ['+ @databasename + '] SET CONCAT_NULL_YIELDS_NULL OFF ;
				ALTER DATABASE ['+ @databasename + '] SET NUMERIC_ROUNDABORT OFF ;
				ALTER DATABASE ['+ @databasename + '] SET QUOTED_IDENTIFIER OFF ;
				ALTER DATABASE ['+ @databasename + '] SET RECURSIVE_TRIGGERS OFF ;
				ALTER DATABASE ['+ @databasename + '] SET  ENABLE_BROKER ;
				ALTER DATABASE ['+ @databasename + '] SET AUTO_UPDATE_STATISTICS_ASYNC ON;
				ALTER DATABASE ['+ @databasename + '] SET DATE_CORRELATION_OPTIMIZATION OFF ;
				ALTER DATABASE ['+ @databasename + '] SET TRUSTWORTHY OFF ;
				ALTER DATABASE ['+ @databasename + '] SET ALLOW_SNAPSHOT_ISOLATION OFF ;
				ALTER DATABASE ['+ @databasename + '] SET PARAMETERIZATION SIMPLE ;
				ALTER DATABASE ['+ @databasename + '] SET READ_COMMITTED_SNAPSHOT OFF ;
				ALTER DATABASE ['+ @databasename + '] SET HONOR_BROKER_PRIORITY OFF ;
				ALTER DATABASE ['+ @databasename + '] SET RECOVERY ' + @recoverymodel + ';
				ALTER DATABASE ['+ @databasename + '] SET  MULTI_USER ;
				ALTER DATABASE ['+ @databasename + '] SET PAGE_VERIFY CHECKSUM  ;
				ALTER DATABASE ['+ @databasename + '] SET DB_CHAINING OFF ;'

			END

	PRINT(@SQL);
	EXECUTE(@SQL);

	select @query;
	exec (@query);

END;