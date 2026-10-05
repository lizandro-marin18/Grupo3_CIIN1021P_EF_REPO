/* =====================================================================
   11_Benchmark_SQLServer.sql - 
   Replica la tabla de hechos x1, x10 y x50 (40 867 / 408 670 / 2 043 350 filas) y mide la MISMA agregación del cuaderno de Spark:
   ventas netas y unidades por plato y canal, con join a Dim_Plato.
   ===================================================================== */
USE DW_Cevicheria;
SET NOCOUNT ON;
GO
DROP TABLE IF EXISTS dbo.Bench_x1, dbo.Bench_x10, dbo.Bench_x50;
CREATE TABLE dbo.Bench_x1  (sk_plato INT NOT NULL, sk_canal INT NOT NULL, importe_neto DECIMAL(10,2) NOT NULL, cantidad INT NOT NULL);
CREATE TABLE dbo.Bench_x10 (sk_plato INT NOT NULL, sk_canal INT NOT NULL, importe_neto DECIMAL(10,2) NOT NULL, cantidad INT NOT NULL);
CREATE TABLE dbo.Bench_x50 (sk_plato INT NOT NULL, sk_canal INT NOT NULL, importe_neto DECIMAL(10,2) NOT NULL, cantidad INT NOT NULL);
DROP TABLE IF EXISTS #n;
SELECT TOP (50) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k INTO #n FROM sys.all_objects;
INSERT dbo.Bench_x1  SELECT f.sk_plato, f.sk_canal, f.importe_neto, f.cantidad FROM dbo.Fact_Ventas f CROSS JOIN #n WHERE #n.k <= 1;
INSERT dbo.Bench_x10 SELECT f.sk_plato, f.sk_canal, f.importe_neto, f.cantidad FROM dbo.Fact_Ventas f CROSS JOIN #n WHERE #n.k <= 10;
INSERT dbo.Bench_x50 SELECT f.sk_plato, f.sk_canal, f.importe_neto, f.cantidad FROM dbo.Fact_Ventas f CROSS JOIN #n WHERE #n.k <= 50;
-- Mismo índice que en el experimento de SQLite (sobre la llave del join)
CREATE INDEX IX_x1  ON dbo.Bench_x1  (sk_plato);
CREATE INDEX IX_x10 ON dbo.Bench_x10 (sk_plato);
CREATE INDEX IX_x50 ON dbo.Bench_x50 (sk_plato);
SELECT 'Bench_x1' AS tabla, COUNT(*) AS filas FROM dbo.Bench_x1 UNION ALL SELECT 'Bench_x10', COUNT(*) FROM dbo.Bench_x10 UNION ALL SELECT 'Bench_x50', COUNT(*) FROM dbo.Bench_x50;   -- 40867 / 408670 / 2043350
GO
/* ---------- Medición ---------- */
DROP TABLE IF EXISTS #res;
CREATE TABLE #res (tabla VARCHAR(10), filas INT, corrida INT, microseg BIGINT);
DECLARE @t VARCHAR(10), @i INT, @f INT, @sql NVARCHAR(MAX), @cnt NVARCHAR(200), @t0 DATETIME2(7);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT v FROM (VALUES ('Bench_x1'), ('Bench_x10'), ('Bench_x50')) x(v);
OPEN c; FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'SELECT p.nombre_plato, f.sk_canal, SUM(f.importe_neto) AS ventas, SUM(f.cantidad) AS unidades INTO #x
                 FROM dbo.' + QUOTENAME(@t) + N' f JOIN dbo.Dim_Plato p ON p.sk_plato = f.sk_plato GROUP BY p.nombre_plato, f.sk_canal;';
    SET @cnt = N'SELECT @n = COUNT(*) FROM dbo.' + QUOTENAME(@t);
    EXEC sys.sp_executesql @cnt, N'@n INT OUTPUT', @n = @f OUTPUT;
    EXEC sys.sp_executesql @sql;                                    -- calentamiento (no se cuenta)
    SET @i = 1;
    WHILE @i <= 3
    BEGIN
        SET @t0 = SYSDATETIME();
        EXEC sys.sp_executesql @sql;
        INSERT #res VALUES (@t, @f, @i, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()));
        SET @i += 1;
    END
    FETCH NEXT FROM c INTO @t;
END
CLOSE c; DEALLOCATE c;
/* ---------- RESULTADO: copie la columna mediana_segundos a la columna "SQL Server" de la Tabla 24 ---------- */
SELECT DISTINCT tabla, filas,
       CAST(PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY microseg) OVER (PARTITION BY tabla) / 1000000.0 AS DECIMAL(10,3)) AS mediana_segundos
FROM #res ORDER BY filas;
SELECT * FROM #res ORDER BY filas, corrida;       -- detalle de las 3 corridas por volumen
GO
/* ---------- Opcional: consultas de negocio sobre el DW real (40 867 filas), con STATISTICS TIME ---------- */
SET STATISTICS TIME ON;
SELECT p.nombre_plato, SUM(f.importe_neto) AS ventas FROM dbo.Fact_Ventas f JOIN dbo.Dim_Plato p ON p.sk_plato = f.sk_plato GROUP BY p.nombre_plato ORDER BY ventas DESC;
SELECT d.anio_mes, c.canal, SUM(f.importe_neto) AS ventas FROM dbo.Fact_Ventas f JOIN dbo.Dim_Fecha d ON d.sk_fecha = f.sk_fecha JOIN dbo.Dim_Canal c ON c.sk_canal = f.sk_canal GROUP BY d.anio_mes, c.canal ORDER BY d.anio_mes, c.canal;
SET STATISTICS TIME OFF;
GO
/* Limpieza (opcional): DROP TABLE dbo.Bench_x1, dbo.Bench_x10, dbo.Bench_x50; */
