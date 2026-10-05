/* =====================================================================
   13_OLAP_Consultas.sql - Operaciones OLAP en T-SQL sobre DW_Cevicheria (ROLLUP, CUBE, GROUPING SETS, slice, dice, drill-down)
   Equivalentes en pandas: olap_kpis.py  |  Equivalentes en DAX: medidas_DAX.md
   ===================================================================== */
USE DW_Cevicheria;
GO
-- ROLL-UP: mes -> trimestre -> año -> total (ROLLUP genera los subtotales)
SELECT d.anio, d.trimestre, d.anio_mes, SUM(f.importe_neto) AS ventas_netas, SUM(f.margen_bruto) AS margen
FROM dbo.Fact_Ventas f JOIN dbo.Dim_Fecha d ON d.sk_fecha = f.sk_fecha
GROUP BY ROLLUP (d.anio, d.trimestre, d.anio_mes) ORDER BY d.anio, d.trimestre, d.anio_mes;
-- DRILL-DOWN: categoría -> plato (se baja un nivel de la jerarquía de Dim_Plato)
SELECT p.categoria, p.nombre_plato, SUM(f.importe_neto) AS ventas_netas, SUM(f.cantidad) AS unidades
FROM dbo.Fact_Ventas f JOIN dbo.Dim_Plato p ON p.sk_plato = f.sk_plato
GROUP BY ROLLUP (p.categoria, p.nombre_plato) ORDER BY p.categoria, ventas_netas DESC;
-- SLICE: se fija UNA dimensión (canal = PedidosYa)
SELECT d.anio_mes, SUM(f.importe_bruto) AS venta_bruta, SUM(f.comision_plataforma) AS comision
FROM dbo.Fact_Ventas f JOIN dbo.Dim_Fecha d ON d.sk_fecha = f.sk_fecha JOIN dbo.Dim_Canal c ON c.sk_canal = f.sk_canal
WHERE c.canal = 'PedidosYa' GROUP BY d.anio_mes ORDER BY d.anio_mes;
-- DICE: se restringen VARIAS dimensiones (T1-2026, Ceviches/Arroces, Yape/Plin)
SELECT p.categoria, g.metodo_pago, SUM(f.importe_neto) AS ventas_netas
FROM dbo.Fact_Ventas f JOIN dbo.Dim_Fecha d ON d.sk_fecha = f.sk_fecha JOIN dbo.Dim_Plato p ON p.sk_plato = f.sk_plato JOIN dbo.Dim_MetodoPago g ON g.sk_pago = f.sk_pago
WHERE d.anio = 2026 AND d.trimestre = 1 AND p.categoria IN ('Ceviches','Arroces') AND g.metodo_pago IN ('Yape','Plin')
GROUP BY p.categoria, g.metodo_pago;
-- CUBO: todas las combinaciones categoría x canal (CUBE) con GROUPING para distinguir subtotales
SELECT p.categoria, c.canal, SUM(f.importe_neto) AS ventas_netas, GROUPING(p.categoria) AS g_cat, GROUPING(c.canal) AS g_canal
FROM dbo.Fact_Ventas f JOIN dbo.Dim_Plato p ON p.sk_plato = f.sk_plato JOIN dbo.Dim_Canal c ON c.sk_canal = f.sk_canal
GROUP BY CUBE (p.categoria, c.canal);
-- GROUPING SETS: solo los niveles que interesan
SELECT d.dia_semana, t.turno, SUM(f.importe_neto) AS ventas_netas
FROM dbo.Fact_Ventas f JOIN dbo.Dim_Fecha d ON d.sk_fecha = f.sk_fecha JOIN dbo.Dim_Turno t ON t.sk_turno = f.sk_turno
GROUP BY GROUPING SETS ((d.dia_semana, t.turno), (d.dia_semana), ());
GO
