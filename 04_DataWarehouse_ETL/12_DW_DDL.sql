/* =====================================================================
   12_DW_DDL.sql - Modelo físico del Data Warehouse (Kimball, esquema en estrella) - SQL Server
   1 tabla de hechos (Fact_Ventas, grano = línea de pedido) + 7 dimensiones. Diagrama: 07_Documentacion/diagramas/modelo_estrella.png
   Carga: BULK INSERT desde DW_csv/ *.csv (generados por etl_cevicheria.py)
   ===================================================================== */
IF DB_ID('DW_Cevicheria') IS NULL CREATE DATABASE DW_Cevicheria;
GO
USE DW_Cevicheria;
GO
/* Re-ejecutable: elimina primero el hecho (tiene las FK) y luego las dimensiones */
DROP TABLE IF EXISTS dbo.Fact_Ventas;
DROP TABLE IF EXISTS dbo.Dim_Fecha, dbo.Dim_Cliente, dbo.Dim_Plato, dbo.Dim_Empleado, dbo.Dim_MetodoPago, dbo.Dim_Canal, dbo.Dim_Turno;
GO
CREATE TABLE dbo.Dim_Fecha (sk_fecha INT NOT NULL PRIMARY KEY, fecha DATE NOT NULL, anio SMALLINT, trimestre TINYINT, mes_num TINYINT, mes_nombre VARCHAR(12),
    anio_mes CHAR(7), semana_iso TINYINT, dia_mes TINYINT, dia_semana_num TINYINT, dia_semana VARCHAR(10), es_fin_semana BIT, es_feriado BIT, nombre_feriado VARCHAR(40) NULL);
CREATE TABLE dbo.Dim_Cliente (sk_cliente INT NOT NULL PRIMARY KEY, id_cliente_nk INT NOT NULL, cliente_seudonimo VARCHAR(12) NOT NULL, dni_hash CHAR(64) NULL,
    distrito VARCHAR(40), tipo_cliente VARCHAR(25), fecha_registro DATE, antiguedad_meses INT, es_cliente_identificado BIT);
CREATE TABLE dbo.Dim_Plato (sk_plato INT NOT NULL PRIMARY KEY, id_plato_nk INT NOT NULL, nombre_plato VARCHAR(100), categoria VARCHAR(30), precio_base DECIMAL(10,2),
    costo_estimado DECIMAL(10,2), margen_unitario DECIMAL(10,2), margen_pct DECIMAL(5,1), rango_precio VARCHAR(20));
CREATE TABLE dbo.Dim_Empleado (sk_empleado INT NOT NULL PRIMARY KEY, id_empleado_nk INT NOT NULL, nombre_completo VARCHAR(110), cargo VARCHAR(30));   -- sin DNI ni salario
CREATE TABLE dbo.Dim_MetodoPago (sk_pago INT NOT NULL PRIMARY KEY, metodo_pago VARCHAR(30), tipo_pago VARCHAR(20));
CREATE TABLE dbo.Dim_Canal (sk_canal INT NOT NULL PRIMARY KEY, canal VARCHAR(20), tipo_canal VARCHAR(20), origen_datos VARCHAR(15));
CREATE TABLE dbo.Dim_Turno (sk_turno INT NOT NULL PRIMARY KEY, turno VARCHAR(20));
CREATE TABLE dbo.Fact_Ventas (
    sk_venta INT NOT NULL PRIMARY KEY,
    sk_fecha INT NOT NULL REFERENCES dbo.Dim_Fecha(sk_fecha), sk_cliente INT NOT NULL REFERENCES dbo.Dim_Cliente(sk_cliente),
    sk_plato INT NOT NULL REFERENCES dbo.Dim_Plato(sk_plato), sk_empleado INT NOT NULL REFERENCES dbo.Dim_Empleado(sk_empleado),
    sk_pago INT NOT NULL REFERENCES dbo.Dim_MetodoPago(sk_pago), sk_canal INT NOT NULL REFERENCES dbo.Dim_Canal(sk_canal), sk_turno INT NOT NULL REFERENCES dbo.Dim_Turno(sk_turno),
    nro_pedido VARCHAR(20) NOT NULL, origen VARCHAR(15) NOT NULL,
    cantidad INT NOT NULL, precio_unitario DECIMAL(10,2) NOT NULL, importe_bruto DECIMAL(10,2) NOT NULL, comision_plataforma DECIMAL(10,2) NOT NULL,
    importe_neto DECIMAL(10,2) NOT NULL, costo_total DECIMAL(10,2) NOT NULL, tiempo_entrega_min INT NULL, calificacion DECIMAL(2,1) NULL, margen_bruto DECIMAL(10,2) NOT NULL);
GO
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Fact_Ventas ON dbo.Fact_Ventas (sk_fecha, sk_plato, sk_canal, sk_cliente, importe_neto, importe_bruto, costo_total, cantidad);   -- acelera agregaciones OLAP
GO

/* ---------- Carga: dimensiones primero, hecho al final (orden por las FK) ---------- */
DECLARE @r VARCHAR(200) = 'C:\Grupo3_CIIN1021P_EF_ENTREGA\Grupo3_CIIN1021P_EF_REPO\04_DataWarehouse_ETL\DW_csv\';

DECLARE @rt VARCHAR(10) = '0x0a'; 
DECLARE @o NVARCHAR(300) = N' WITH (FORMAT=''CSV'', FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''' + @rt + N''', CODEPAGE=''65001'', KEEPNULLS, TABLOCK);';
EXEC(N'BULK INSERT dbo.Dim_Fecha      FROM ''' + @r + 'dim_fecha.csv''' + @o);
EXEC(N'BULK INSERT dbo.Dim_Cliente    FROM ''' + @r + 'dim_cliente.csv''' + @o);
EXEC(N'BULK INSERT dbo.Dim_Plato      FROM ''' + @r + 'dim_plato.csv''' + @o);
EXEC(N'BULK INSERT dbo.Dim_Empleado   FROM ''' + @r + 'dim_empleado.csv''' + @o);
EXEC(N'BULK INSERT dbo.Dim_MetodoPago FROM ''' + @r + 'dim_metodo_pago.csv''' + @o);
EXEC(N'BULK INSERT dbo.Dim_Canal      FROM ''' + @r + 'dim_canal.csv''' + @o);
EXEC(N'BULK INSERT dbo.Dim_Turno      FROM ''' + @r + 'dim_turno.csv''' + @o);
EXEC(N'BULK INSERT dbo.Fact_Ventas    FROM ''' + @r + 'fact_ventas.csv''' + @o);
GO

/* ---------- Verificación: debe dar Fact_Ventas = 40 867; Dim_Fecha = 457; Dim_Cliente = 5 502; Dim_Plato = 40; Dim_Empleado = 26; 5 / 5 / 4 ---------- */
SELECT 'Fact_Ventas' t, COUNT(*) filas FROM dbo.Fact_Ventas UNION ALL SELECT 'Dim_Fecha', COUNT(*) FROM dbo.Dim_Fecha UNION ALL
SELECT 'Dim_Cliente', COUNT(*) FROM dbo.Dim_Cliente UNION ALL SELECT 'Dim_Plato', COUNT(*) FROM dbo.Dim_Plato UNION ALL SELECT 'Dim_Empleado', COUNT(*) FROM dbo.Dim_Empleado UNION ALL
SELECT 'Dim_MetodoPago', COUNT(*) FROM dbo.Dim_MetodoPago UNION ALL SELECT 'Dim_Canal', COUNT(*) FROM dbo.Dim_Canal UNION ALL SELECT 'Dim_Turno', COUNT(*) FROM dbo.Dim_Turno;
SELECT COUNT(*) AS ventas_netas_filas, CAST(SUM(importe_neto) AS DECIMAL(12,2)) AS ventas_netas FROM dbo.Fact_Ventas;   -- esperado: 40867 y 1695893.98

/* NULL esperados (NO son error): Dim_Cliente.dni_hash es NULL en 34 filas (cliente de paso, cliente app y 32 DNI inválidos);
   Fact_Ventas.tiempo_entrega_min y calificacion son NULL en las ventas del salón (solo existen en las apps). */
SELECT SUM(CASE WHEN dni_hash IS NULL THEN 1 ELSE 0 END) AS dni_hash_nulos FROM dbo.Dim_Cliente;
GO