/* =====================================================================
   07_Indices_Rendimiento.sql - Análisis de plan de ejecución y optimización con ÍNDICES (Pedido: 11 982 filas; Detalle: 35 467)
   ===================================================================== */
USE Cevicheria_DB;
GO
SET STATISTICS IO ON; SET STATISTICS TIME ON;
DBCC DROPCLEANBUFFERS;   -- solo en entornos de prueba
GO
/* Consulta crítica Q1: ventas por rango de fechas (tablero diario) */
-- ANTES: sin índice sobre fecha_pedido -> Clustered Index Scan de toda la tabla
DROP INDEX IF EXISTS IX_Pedido_Fecha ON dbo.Pedido;
SELECT fecha_pedido, COUNT(*) AS pedidos, SUM(monto_total) AS ventas
FROM dbo.Pedido WHERE fecha_pedido BETWEEN '2026-03-01' AND '2026-03-07' GROUP BY fecha_pedido;
GO
-- DESPUÉS: índice no agrupado con columnas incluidas (cubre la consulta -> Index Seek, sin Key Lookup)
CREATE NONCLUSTERED INDEX IX_Pedido_Fecha ON dbo.Pedido (fecha_pedido) INCLUDE (monto_total, id_cliente);
GO
SELECT fecha_pedido, COUNT(*) AS pedidos, SUM(monto_total) AS ventas
FROM dbo.Pedido WHERE fecha_pedido BETWEEN '2026-03-01' AND '2026-03-07' GROUP BY fecha_pedido;
GO
/* Consulta crítica Q2: platos más vendidos de un mes (join Pedido-Detalle-Plato) */
DROP INDEX IF EXISTS IX_Detalle_Plato ON dbo.Detalle_Pedido;
DROP INDEX IF EXISTS IX_Pedido_Fecha ON dbo.Pedido
SELECT TOP 10 pl.nombre_plato, SUM(d.cantidad) AS unidades
FROM dbo.Pedido p JOIN dbo.Detalle_Pedido d ON d.id_pedido = p.id_pedido JOIN dbo.Plato pl ON pl.id_plato = d.id_plato
WHERE p.fecha_pedido BETWEEN '2026-03-01' AND '2026-03-31' GROUP BY pl.nombre_plato ORDER BY unidades DESC;
GO
SET STATISTICS IO on; SET STATISTICS TIME on;


CREATE NONCLUSTERED INDEX IX_Detalle_Plato ON dbo.Detalle_Pedido (id_plato) INCLUDE (id_pedido, cantidad);
GO
SELECT TOP 10 pl.nombre_plato, SUM(d.cantidad) AS unidades
FROM dbo.Pedido p JOIN dbo.Detalle_Pedido d ON d.id_pedido = p.id_pedido JOIN dbo.Plato pl ON pl.id_plato = d.id_plato
WHERE p.fecha_pedido BETWEEN '2026-03-01' AND '2026-03-31' GROUP BY pl.nombre_plato ORDER BY unidades DESC;
GO
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
/* Registrar: lecturas lógicas (logical reads), tiempo de CPU/transcurrido (ms), operador principal (Scan/Seek), costo estimado del subárbol. */
