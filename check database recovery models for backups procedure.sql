		 declare @backup_type varchar(1)
		 declare @dbname varchar(300)
		 declare @INCSIMPLE varchar(1)
		 declare @ignoredb varchar(1)

		 set @INCSIMPLE = 'Y'
		 set @backup_type = 'T'
		set @dbname = ''
		set @ignoredb = 'N'
		
	if @dbname<> ''
Begin
	SET @dbname = ',' + @dbname + ','
end
	
-- ######### 
		
	-- Recovery model 
	-- 1 = FULL
	-- 2 = BULK_LOGGED
	-- 3 = SIMPLE
 

select 
				d.name,
				m.mirroring_role
				from sys.databases d
				inner join sys.database_mirroring m
				on d.database_id = m.database_id
				-- Full Database backups
				--where d.state_desc <> UPPER('restoring') -- ignore any restoring databases
				where d.state not in (1,2,3,6) -- ignore restoring, recovering, recovery pending and offline databases
				and is_in_standby = 0 -- ignore databases that are in standby mode for log shipping
				and (d.source_database_id is NULL) -- ignore all database snapshots 
				and (
				-- Full Database Backups
						(
							@backup_type = 'F' and @dbname = ''
							and
							-- Pick up ALL SIMPLE mode db's apart from TEMPDB & MODEL, as well as ALL FULL mode databases
							((d.recovery_model = 3 and d.database_id  NOT IN (2,3) and @INCSIMPLE = 'Y' 
							or (d.recovery_model in (1,2) or m.mirroring_role <> 1)) -- ignore databases acting as a mirror
							-- Pick up Master & MSDB in SIMPLE mode as well as ALL FULL/BULK-LOGGED mode databases
							or (d.recovery_model = 3 and d.database_id  IN (1,4) or d.recovery_model in (1,2) and @INCSIMPLE <> 'Y') 
							and d.source_database_id is NULL) -- ignore all database snapshots 	
						)
					-- Differential backups -- ignore all SIMPLE mode databases
					or (
							@backup_type = 'D' and @dbname = ''
							and
							-- Pick up all other FULL recovery mode databases
							(((d.recovery_model in (1,2) or m.mirroring_role <> 1)	-- ignore databases acting as a mirror
							-- Pick up all SIMPLE mode databases not including system db's
							or (d.recovery_model = 3 and @INCSIMPLE = 'Y' and d.database_id  NOT IN (1,2,3,4)))
							and d.source_database_id is NULL) -- ignore all database snapshots		
						)
					-- Transaction Log Backups
					or (
							-- Pick up all other FULL/BULK-LOGGED recovery mode databases
							@backup_type = 'T' and @dbname = ''
							and
							(((d.recovery_model = 1  
							or d.recovery_model = 2) or m.mirroring_role <> 1 ) -- ignore databases acting as a mirror
							and d.database_id  NOT IN (1,2,3,4)
							and d.source_database_id is NULL) -- ignore all database snapshots
						)
						-- Master & MSDB only
					or
						(
							-- Pick up MASTER & MSDB system databases only
							@backup_type = 'S' and @dbname = ''
							and (d.recovery_model = 3 and d.database_id  IN (1,4))
						)
						-- adhoc database backups
					or 
						(
							-- Pick up only the database that has been passed into the procedure
							
							--#################### COMMENTED OUT ON 01/09/2010 ###############################
							--(@dbname = d.name
							--and @dbname <> '') -- will only pick up a single database name passed into the procedure as a parameter
							-- #### NEW ADDED  ON 01/09/2010 ####
							
							-- added to ignore databases that are passed in as they are either backed up elsewhere or don't need backing up
							--or (@dbname <> '' and NOT (CHARINDEX(',' + d.name + ',' , @dbname) > 0) and d.database_id  NOT IN (2,3) and @ignoredb = 'Y')
							(@dbname <> '' and NOT (CHARINDEX(',' + d.name + ',' , @dbname) > 0) and d.database_id  NOT IN (2,3) and @ignoredb = 'Y')
							-- added to only process multiple databases that are passed in as a parameter
							or (@dbname <> '' and  (CHARINDEX(',' + d.name + ',' , @dbname) > 0) and @ignoredb = 'N')
							-- #### NEW END ####
							and 
							(
							((@backup_type = 'F'
							or (@backup_type = 'T' and d.database_id  NOT IN (1,2,3,4)) -- ignore all system databases if backup type TX
							or (@backup_type = 'D' and d.database_id  NOT IN (1,2,3,4)) -- ignore all system databases if backup type Diff
							) or m.mirroring_role <> 1)
							or (@backup_type = 'S' and d.database_id  IN (1,4)) -- ignore model and tempdb databases if backup type System
							)
						) 			
					)
						order by d.name