/* =====================================================================
   10_Export_CSV_para_DW.sql - Exportar desde SQL Server a CSV (insumo del ETL en pandas)
   Las vistas vw_DW_* aplican minimización y seudonimización (Ley 29733): NO exponen DNI, email, teléfono ni salario.
   Ejecutar los comandos bcp en CMD (autenticación Windows -T; UTF-8 con -C 65001). Salida -> 00_Datos/Export_SQL
   ===================================================================== */
USE Cevicheria_DB;
GO
CREATE OR ALTER VIEW dbo.vw_DW_Pedido  AS SELECT id_pedido, fecha_pedido, hora_pedido, id_cliente, id_empleado, canal_interno, metodo_pago, monto_total, fecha_imputada FROM dbo.Pedido;
GO
CREATE OR ALTER VIEW dbo.vw_DW_Detalle AS SELECT id_detalle, id_pedido, id_plato, cantidad, precio_unitario, subtotal FROM dbo.Detalle_Pedido;
GO
CREATE OR ALTER VIEW dbo.vw_DW_Plato   AS SELECT id_plato, nombre_plato, categoria, precio_base, costo_estimado FROM dbo.Plato;
GO
/* --- Comandos bcp (CMD). Se antepone la fila de cabecera con -h o con un UNION ALL en el queryout --- */
-- bcp "SELECT 'id_pedido','fecha_pedido','hora_pedido','id_cliente','id_empleado','canal_interno','metodo_pago','monto_total','fecha_imputada' UNION ALL SELECT CAST(id_pedido AS VARCHAR),CONVERT(VARCHAR(10),fecha_pedido,23),CONVERT(VARCHAR(8),hora_pedido,108),CAST(id_cliente AS VARCHAR),CAST(id_empleado AS VARCHAR),canal_interno,metodo_pago,CAST(monto_total AS VARCHAR),CAST(fecha_imputada AS VARCHAR) FROM Cevicheria_DB.dbo.vw_DW_Pedido" queryout "C:\Proyecto\00_Datos\Export_SQL\Pedido.csv" -c -t, -C 65001 -S localhost -T
-- bcp "SELECT * FROM Cevicheria_DB.dbo.vw_DW_Detalle" queryout "C:\Proyecto\00_Datos\Export_SQL\Detalle_Pedido.csv" -c -t, -C 65001 -S localhost -T
-- bcp "SELECT * FROM Cevicheria_DB.dbo.vw_DW_Plato"   queryout "C:\Proyecto\00_Datos\Export_SQL\Plato.csv" -c -t, -C 65001 -S localhost -T
GO
