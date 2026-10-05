/* =====================================================================
   08_Backup_Restore.sql - Política de respaldo FULL + DIFFERENTIAL + LOG (RPO <= 15 min; RTO <= 30 min)
   Ley 29733 Art. 16 y ISO 27001 A.8.13 (copia de seguridad de la información)
   Política: FULL domingo 03:00 | DIFFERENTIAL diario 03:00 (lun-sáb) | LOG cada 15 min en horario de atención (10:00-23:00)
   ===================================================================== */

USE master;
GO
ALTER DATABASE Cevicheria_DB SET RECOVERY FULL;                              -- necesario para respaldos de log
GO
BACKUP DATABASE Cevicheria_DB TO DISK = 'C:\Backups\Cevicheria_DB_FULL.bak'
  WITH INIT, FORMAT, CHECKSUM, COMPRESSION, NAME = 'Full semanal', STATS = 10;
BACKUP DATABASE Cevicheria_DB TO DISK = 'C:\Backups\Cevicheria_DB_DIFF.bak'
  WITH DIFFERENTIAL, INIT, CHECKSUM, COMPRESSION, NAME = 'Diferencial diario', STATS = 10;
BACKUP LOG Cevicheria_DB TO DISK = 'C:\Backups\Cevicheria_DB_LOG.trn' WITH INIT, CHECKSUM, COMPRESSION, NAME = 'Log 15 min';
GO
/* Verificación de integridad de los archivos (no restaura, comprueba legibilidad y checksum) */
RESTORE VERIFYONLY FROM DISK = 'C:\Backups\Cevicheria_DB_FULL.bak' WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = 'C:\Backups\Cevicheria_DB_DIFF.bak' WITH CHECKSUM;
GO
/* ---------- Prueba de restauración en una base de PRUEBA (no toca producción) ---------- */
RESTORE FILELISTONLY FROM DISK = 'C:\Backups\Cevicheria_DB_FULL.bak';        -- obtener nombres lógicos de archivos
RESTORE DATABASE Cevicheria_DB_TEST FROM DISK = 'C:\Backups\Cevicheria_DB_FULL.bak'
  WITH NORECOVERY, REPLACE,
       MOVE 'Cevicheria_DB'     TO 'C:\Backups\Test\Cevicheria_DB_TEST.mdf',
       MOVE 'Cevicheria_DB_log' TO 'C:\Backups\Test\Cevicheria_DB_TEST.ldf';
RESTORE DATABASE Cevicheria_DB_TEST FROM DISK = 'C:\Backups\Cevicheria_DB_DIFF.bak' WITH NORECOVERY;
RESTORE LOG      Cevicheria_DB_TEST FROM DISK = 'C:\Backups\Cevicheria_DB_LOG.trn'  WITH RECOVERY;
GO
SELECT 'Original' origen, COUNT(*) filas FROM Cevicheria_DB.dbo.Pedido UNION ALL SELECT 'Restaurada', COUNT(*) FROM Cevicheria_DB_TEST.dbo.Pedido;   -- deben coincidir
GO
/* ---------- Restauración (producción): expulsa usuarios, restaura FULL + DIFF + LOG ---------- */
ALTER DATABASE Cevicheria_DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE Cevicheria_DB FROM DISK = 'C:\Backups\Cevicheria_DB_FULL.bak' WITH NORECOVERY, REPLACE;
RESTORE DATABASE Cevicheria_DB FROM DISK = 'C:\Backups\Cevicheria_DB_DIFF.bak' WITH NORECOVERY;
RESTORE LOG      Cevicheria_DB FROM DISK = 'C:\Backups\Cevicheria_DB_LOG.trn'  WITH RECOVERY;
ALTER DATABASE Cevicheria_DB SET MULTI_USER;
GO
/* ---------- Automatización con SQL Server Agent (esqueleto del trabajo semanal FULL) ---------- */
USE msdb;
GO
EXEC dbo.sp_add_job @job_name = N'Cevicheria_Backup_FULL_Semanal';
EXEC dbo.sp_add_jobstep @job_name = N'Cevicheria_Backup_FULL_Semanal', @step_name = N'FULL', @subsystem = N'TSQL', @database_name = N'master',
     @command = N'BACKUP DATABASE Cevicheria_DB TO DISK = ''C:\Backups\Cevicheria_DB_FULL.bak'' WITH INIT, CHECKSUM, COMPRESSION;';
EXEC dbo.sp_add_jobschedule @job_name = N'Cevicheria_Backup_FULL_Semanal', @name = N'Domingo 03:00', @freq_type = 8, @freq_interval = 1, @freq_recurrence_factor = 1, @active_start_time = 30000;
EXEC dbo.sp_add_jobserver @job_name = N'Cevicheria_Backup_FULL_Semanal';
GO
