/* =====================================================================
   02_Funciones.sql  -  1 función escalar + 1 escalar de validación + 1 con valor de tabla
   ===================================================================== */
USE Cevicheria_DB;
GO
/* F1 (escalar) categoriza el monto de un pedido. */
CREATE OR ALTER FUNCTION dbo.fn_CategoriaVenta (@monto DECIMAL(10,2))
RETURNS VARCHAR(20)
AS
BEGIN
    RETURN CASE WHEN @monto IS NULL THEN 'Sin monto' WHEN @monto > 150.00 THEN 'Venta Grande' ELSE 'Venta Pequeña' END;
END;
GO
/* F2 (escalar) valida un DNI: exactamente 8 dígitos numéricos. Devuelve 1 (válido) / 0 (inválido).
   Se usa en sp_CargaMasivaClientes (regla R5) y en el CHECK de nuevos registros. */
CREATE OR ALTER FUNCTION dbo.fn_ValidarDNI (@dni VARCHAR(20))
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN @dni IS NOT NULL AND LEN(@dni) = 8 AND @dni NOT LIKE '%[^0-9]%' THEN 1 ELSE 0 END;
END;
GO
/* F3 (con valor de tabla, en línea) ventas de un rango de fechas agrupadas por categoría de plato.
   Reutilizable por Power BI, por procedimientos y por el rol de analista. */
CREATE OR ALTER FUNCTION dbo.fn_VentasPorCategoria (@desde DATE, @hasta DATE)
RETURNS TABLE
AS
RETURN
(
    SELECT pl.categoria, COUNT(DISTINCT p.id_pedido) AS pedidos, SUM(d.cantidad) AS unidades, SUM(d.subtotal) AS ventas,
           SUM(d.subtotal - d.cantidad * pl.costo_estimado) AS margen_bruto
    FROM dbo.Pedido p
    JOIN dbo.Detalle_Pedido d ON d.id_pedido = p.id_pedido
    JOIN dbo.Plato pl         ON pl.id_plato = d.id_plato
    WHERE p.fecha_pedido BETWEEN @desde AND @hasta
    GROUP BY pl.categoria
);
GO
