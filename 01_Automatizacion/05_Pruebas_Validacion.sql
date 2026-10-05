/* =====================================================================
   05_Pruebas_Validacion.sql  -  Pruebas de humo de SP, triggers y funciones (ejecutar en SSMS y capturar resultados)
   Orden: 01 -> 02 -> 03 -> 04 -> 09_Carga_Datos.sql -> este script
   ===================================================================== */
USE Cevicheria_DB;
GO
PRINT '--- P1 sp_IngresarPedido con cliente NULL -> 9999 y 3 líneas (1 con plato inexistente: SAVEPOINT)';
DECLARE @l dbo.tvp_LineaPedido;
INSERT INTO @l VALUES (900001, 1, 2), (900002, 9, 1), (900003, 999, 1);        -- 999 no existe -> se revierte solo esa línea
EXEC dbo.sp_IngresarPedido @id_pedido = 900001, @id_cliente = NULL, @id_empleado = 16, @canal = 'Salón', @metodo_pago = 'Yape', @lineas = @l;
SELECT * FROM dbo.Pedido WHERE id_pedido = 900001;  SELECT * FROM dbo.Detalle_Pedido WHERE id_pedido = 900001;
GO
PRINT '--- P2 sp_IngresarPedido (error): pedido sin líneas válidas -> ROLLBACK total';
DECLARE @l2 dbo.tvp_LineaPedido; INSERT INTO @l2 VALUES (900010, 999, 1);
EXEC dbo.sp_IngresarPedido 900002, 10, 16, 'Salón', 'Efectivo', @l2;
SELECT COUNT(*) AS debe_ser_0 FROM dbo.Pedido WHERE id_pedido = 900002;
GO
PRINT '--- P3 trigger de integridad: monto negativo bloqueado';
BEGIN TRY
    INSERT INTO dbo.Pedido (id_pedido, fecha_pedido, id_cliente, id_empleado, canal_interno, metodo_pago, monto_total) VALUES (900003, '2026-09-28', 10, 16, 'Salón', 'Yape', -10.00);
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS numero, ERROR_MESSAGE() AS mensaje; END CATCH
GO
PRINT '--- P4 sp_ActualizarSalario (feliz y con error) + trigger de auditoría (valor anterior/nuevo)';
EXEC dbo.sp_ActualizarSalario 16, 1800.00;
EXEC dbo.sp_ActualizarSalario 16, 500.00;               -- ROLLBACK
EXEC dbo.sp_ActualizarSalario 9999, 1800.00;            -- empleado inexistente
GO
PRINT '--- P5 el log es inmutable: intento de borrar la auditoría';
BEGIN TRY DELETE FROM dbo.Log_Auditoria; END TRY BEGIN CATCH SELECT ERROR_NUMBER() AS numero, ERROR_MESSAGE() AS mensaje; END CATCH
GO
PRINT '--- P6 funciones';
SELECT dbo.fn_CategoriaVenta(200) AS grande, dbo.fn_CategoriaVenta(50) AS pequena, dbo.fn_ValidarDNI('12345678') AS dni_ok, dbo.fn_ValidarDNI('1234567') AS dni_mal;
SELECT * FROM dbo.fn_VentasPorCategoria('2026-01-01', '2026-03-31') ORDER BY ventas DESC;
GO
PRINT '--- Resultado: log de auditoría y de errores con registros de prueba';
SELECT TOP 20 * FROM dbo.Log_Auditoria ORDER BY id_log DESC;
SELECT TOP 20 * FROM dbo.Log_Errores  ORDER BY id_error DESC;
GO
