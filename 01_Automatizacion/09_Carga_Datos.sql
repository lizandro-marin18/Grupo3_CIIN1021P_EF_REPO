/* =====================================================================
   09_Carga_Datos.sql  -  Carga inicial de maestros y ejecución de las cargas masivas (ajustar @base ruta)
   Los CSV crudos están en 00_Datos/Crudos. 
   ===================================================================== */
USE Cevicheria_DB;
GO
-- 1) Maestros pequeños (Plato, Empleado): se cargan con BULK INSERT directo a tabla temporal y luego INSERT
CREATE TABLE #pl (id_plato INT, nombre_plato VARCHAR(100), categoria VARCHAR(30), precio_base DECIMAL(10,2), costo_estimado DECIMAL(10,2));
EXEC('BULK INSERT #pl FROM ''C:\Grupo3_CIIN1021P_EF_ENTREGA\Grupo3_CIIN1021P_EF_REPO\00_Datos\Crudos\Platos_Cevicheria.csv'' WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''0x0a'', CODEPAGE=''65001'')');
INSERT INTO dbo.Plato SELECT * FROM #pl;
CREATE TABLE #em (id_empleado INT, dni_empleado VARCHAR(20), nombre VARCHAR(50), apellido VARCHAR(50), cargo VARCHAR(30), salario_mensual VARCHAR(20));
EXEC('BULK INSERT #em FROM ''C:\Grupo3_CIIN1021P_EF_ENTREGA\Grupo3_CIIN1021P_EF_REPO\00_Datos\Crudos\Personal_Cevicheria.csv'' WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''0x0a'', CODEPAGE=''65001'')');
INSERT INTO dbo.Empleado (id_empleado, dni_empleado, nombre, apellido, cargo, salario_mensual)
SELECT id_empleado, RIGHT('00000000' + dni_empleado, 8), nombre, apellido, cargo, TRY_CAST(NULLIF(salario_mensual, '') AS DECIMAL(10,2)) FROM #em;
-- 2) Cargas masivas con validación (reglas R1-R6): clientes primero (FK), luego pedidos y detalle
EXEC dbo.sp_CargaMasivaClientes @ruta = 'C:\Grupo3_CIIN1021P_EF_ENTREGA\Grupo3_CIIN1021P_EF_REPO\00_Datos\Crudos\Clientes_Cevicheria.csv';
EXEC dbo.sp_CargaMasivaPedidos  @ruta_pedidos = 'C:\Grupo3_CIIN1021P_EF_ENTREGA\Grupo3_CIIN1021P_EF_REPO\00_Datos\Crudos\Pedidos_Cevicheria.csv', @ruta_detalle = 'C:\Grupo3_CIIN1021P_EF_ENTREGA\Grupo3_CIIN1021P_EF_REPO\00_Datos\Crudos\Detalle_Pedido_Cevicheria.csv';
-- 3) Asistencia
CREATE TABLE #as (id_asistencia INT, id_empleado INT, fecha DATE, hora_ingreso TIME(0), horas_trabajadas DECIMAL(5,2), tardanza_min INT);
EXEC('BULK INSERT #as FROM ''C:\Grupo3_CIIN1021P_EF_ENTREGA\Grupo3_CIIN1021P_EF_REPO\00_Datos\Crudos\Asistencia_Personal.csv'' WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''0x0a'', CODEPAGE=''65001'')');
INSERT INTO dbo.Asistencia SELECT * FROM #as;
GO
-- Verificación
SELECT 'Cliente' t, COUNT(*) n FROM dbo.Cliente UNION ALL SELECT 'Pedido', COUNT(*) FROM dbo.Pedido UNION ALL SELECT 'Detalle_Pedido', COUNT(*) FROM dbo.Detalle_Pedido
UNION ALL SELECT 'Log_Errores', COUNT(*) FROM dbo.Log_Errores UNION ALL SELECT 'Log_Auditoria', COUNT(*) FROM dbo.Log_Auditoria;
GO
