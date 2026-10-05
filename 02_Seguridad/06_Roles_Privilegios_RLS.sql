/* =====================================================================
   06_Roles_Privilegios_RLS.sql - Seguridad conforme a Ley N.° 29733 (Arts. 8, 9, 11, 16 y 17) e ISO/IEC 27001:2022 (A.5.15, A.5.18, A.8.3, A.8.15)
   6 roles con privilegios diferenciados + enmascaramiento dinámico (DDM) + Row-Level Security (RLS) para clientes.
   Principios: mínimo privilegio, segregación de funciones, minimización de datos personales, trazabilidad.
   ===================================================================== */
USE Cevicheria_DB;
GO
/* ---------- 1. Roles ---------- */
IF DATABASE_PRINCIPAL_ID('Rol_Administrador') IS NULL CREATE ROLE Rol_Administrador;  
IF DATABASE_PRINCIPAL_ID('Rol_AnalistaDatos') IS NULL CREATE ROLE Rol_AnalistaDatos;   
IF DATABASE_PRINCIPAL_ID('Rol_Auditor')       IS NULL CREATE ROLE Rol_Auditor;         
IF DATABASE_PRINCIPAL_ID('Rol_Vendedor')      IS NULL CREATE ROLE Rol_Vendedor;        -- mozo/vendedor/cajero: registra ventas
IF DATABASE_PRINCIPAL_ID('Rol_Cliente')       IS NULL CREATE ROLE Rol_Cliente;         -- cliente registrado: ve solo SUS pedidos
IF DATABASE_PRINCIPAL_ID('Rol_Cocina')        IS NULL CREATE ROLE Rol_Cocina;          -- cocina: ve qué preparar, sin montos ni clientes
GO
/* ---------- 2. Vistas de mínimo privilegio ---------- */
CREATE OR ALTER VIEW dbo.vw_DW_Cliente AS      
    SELECT id_cliente, CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('LaEsquina2026', dni)), 2) AS dni_hash,
           distrito, tipo_cliente, fecha_registro FROM dbo.Cliente;
GO
CREATE OR ALTER VIEW dbo.vw_DW_Empleado AS SELECT id_empleado, nombre + ' ' + apellido AS nombre_completo, cargo FROM dbo.Empleado;   -- sin DNI ni salario
GO
CREATE OR ALTER VIEW dbo.vw_MisPedidos AS SELECT id_pedido, fecha_pedido, canal_interno, metodo_pago, monto_total FROM dbo.Pedido;    -- RLS filtra por cliente
GO
CREATE OR ALTER VIEW dbo.vw_PedidosCocina AS
    SELECT p.id_pedido, p.hora_pedido, p.canal_interno, pl.nombre_plato, d.cantidad
    FROM dbo.Pedido p JOIN dbo.Detalle_Pedido d ON d.id_pedido = p.id_pedido JOIN dbo.Plato pl ON pl.id_plato = d.id_plato
    WHERE p.fecha_pedido = CAST(SYSDATETIME() AS DATE);
GO
/* ---------- 3. Privilegios ---------- */
-- Administrador: CRUD de negocio; ve la auditoría pero NO puede alterarla (además lo impide el trigger INSTEAD OF)
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Pedido          TO Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Detalle_Pedido  TO Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Cliente         TO Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Empleado        TO Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Plato           TO Rol_Administrador;
GRANT EXECUTE ON SCHEMA::dbo TO Rol_Administrador;
GRANT SELECT ON dbo.Log_Auditoria TO Rol_Administrador;  DENY INSERT, UPDATE, DELETE ON dbo.Log_Auditoria TO Rol_Administrador;
GRANT UNMASK TO Rol_Administrador;
-- Analista de datos: solo lectura de vistas seudonimizadas y hechos; sin acceso a tablas con datos personales
GRANT SELECT ON dbo.vw_DW_Cliente TO Rol_AnalistaDatos;   GRANT SELECT ON dbo.vw_DW_Empleado TO Rol_AnalistaDatos;
GRANT SELECT ON dbo.Pedido TO Rol_AnalistaDatos;          GRANT SELECT ON dbo.Detalle_Pedido TO Rol_AnalistaDatos;   GRANT SELECT ON dbo.Plato TO Rol_AnalistaDatos;
GRANT SELECT ON dbo.fn_VentasPorCategoria TO Rol_AnalistaDatos;
DENY SELECT ON dbo.Cliente TO Rol_AnalistaDatos;          DENY SELECT ON dbo.Empleado TO Rol_AnalistaDatos;
DENY SELECT ON dbo.Log_Auditoria TO Rol_AnalistaDatos;    DENY SELECT ON dbo.Log_Errores TO Rol_AnalistaDatos;
-- Auditor: solo logs (no ve datos del negocio) - segregación de funciones (ISO 27001 A.5.3)
GRANT SELECT ON dbo.Log_Auditoria TO Rol_Auditor;         GRANT SELECT ON dbo.Log_Errores TO Rol_Auditor;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Pedido TO Rol_Auditor;   DENY SELECT ON dbo.Empleado TO Rol_Auditor;   DENY SELECT ON dbo.Cliente TO Rol_Auditor;
-- Vendedor: registra ventas solo mediante el SP; ve carta y datos mínimos del cliente; No ve salarios ni DNI
GRANT EXECUTE ON dbo.sp_IngresarPedido TO Rol_Vendedor;   GRANT EXECUTE ON TYPE::dbo.tvp_LineaPedido TO Rol_Vendedor;
GRANT SELECT ON dbo.Plato TO Rol_Vendedor;                GRANT SELECT (id_cliente, nombre, apellido, tipo_cliente) ON dbo.Cliente TO Rol_Vendedor;
DENY DELETE, UPDATE ON dbo.Pedido TO Rol_Vendedor;        DENY SELECT ON dbo.Empleado TO Rol_Vendedor;   DENY SELECT ON dbo.Log_Auditoria TO Rol_Vendedor;
-- Cliente: solo su historial (RLS) y la carta
GRANT SELECT ON dbo.vw_MisPedidos TO Rol_Cliente;         GRANT SELECT ON dbo.Plato TO Rol_Cliente;
DENY SELECT ON dbo.Empleado TO Rol_Cliente;               DENY SELECT ON dbo.Log_Auditoria TO Rol_Cliente;    DENY SELECT ON dbo.Cliente TO Rol_Cliente;
-- Cocina: solo la vista de preparación
GRANT SELECT ON dbo.vw_PedidosCocina TO Rol_Cocina;       DENY SELECT ON dbo.Pedido TO Rol_Cocina;   DENY SELECT ON dbo.Cliente TO Rol_Cocina;
GO
/* ---------- 4. Enmascaramiento dinámico ---------- */
-- Cliente.dni NO se enmascara: vw_DW_Cliente calcula el hash sobre el DNI real; su protección es por permisos de columna (Vendedor) y DENY (Analista, Auditor, Cliente, Cocina).
ALTER TABLE dbo.Cliente  ALTER COLUMN email    ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE dbo.Cliente  ALTER COLUMN telefono ADD MASKED WITH (FUNCTION = 'partial(0,"XXXXX",4)');
ALTER TABLE dbo.Empleado ALTER COLUMN dni_empleado ADD MASKED WITH (FUNCTION = 'partial(0,"XXXX",4)');
ALTER TABLE dbo.Empleado ALTER COLUMN salario_mensual ADD MASKED WITH (FUNCTION = 'default()');
GO
/* ---------- 5.  un cliente solo ve sus pedidos ---------- */
CREATE SCHEMA seg AUTHORIZATION dbo;
GO
CREATE OR ALTER FUNCTION seg.fn_FiltroPedidoCliente (@id_cliente INT)
RETURNS TABLE WITH SCHEMABINDING
AS RETURN
    SELECT 1 AS permitido
    WHERE IS_MEMBER('Rol_Cliente') = 0 OR IS_MEMBER('db_owner') = 1                       -- los demás roles no se filtran
       OR @id_cliente = (SELECT c.id_cliente FROM dbo.Cliente c WHERE c.usuario_bd = USER_NAME());
GO
CREATE SECURITY POLICY seg.PoliticaPedidoCliente ADD FILTER PREDICATE seg.fn_FiltroPedidoCliente(id_cliente) ON dbo.Pedido WITH (STATE = ON);
GO
/* ---------- 6. Usuarios de prueba (sin login) y verificación ---------- */
CREATE USER u_admin    WITHOUT LOGIN; ALTER ROLE Rol_Administrador ADD MEMBER u_admin;
CREATE USER u_analista WITHOUT LOGIN; ALTER ROLE Rol_AnalistaDatos ADD MEMBER u_analista;
CREATE USER u_auditor  WITHOUT LOGIN; ALTER ROLE Rol_Auditor       ADD MEMBER u_auditor;
CREATE USER u_vendedor WITHOUT LOGIN; ALTER ROLE Rol_Vendedor      ADD MEMBER u_vendedor;
CREATE USER u_cliente1 WITHOUT LOGIN; ALTER ROLE Rol_Cliente       ADD MEMBER u_cliente1;
CREATE USER u_cocina   WITHOUT LOGIN; ALTER ROLE Rol_Cocina        ADD MEMBER u_cocina;
UPDATE dbo.Cliente SET usuario_bd = 'u_cliente1' WHERE id_cliente = 1;
GO
PRINT '--- T1 analista: puede leer vista seudonimizada; NO puede leer Empleado (salarios)';
EXECUTE AS USER = 'u_analista'; SELECT TOP 3 * FROM dbo.vw_DW_Cliente;
BEGIN TRY SELECT TOP 1 salario_mensual FROM dbo.Empleado; END TRY BEGIN CATCH SELECT ERROR_MESSAGE() AS denegado; END CATCH REVERT;
PRINT '--- T2 vendedor: no puede borrar pedidos ni leer auditoría';
EXECUTE AS USER = 'u_vendedor'; BEGIN TRY DELETE FROM dbo.Pedido WHERE id_pedido = 1; END TRY BEGIN CATCH SELECT ERROR_MESSAGE() AS denegado; END CATCH REVERT;
PRINT '--- T3 cliente 1 solo ve sus pedidos (RLS)';
EXECUTE AS USER = 'u_cliente1'; SELECT COUNT(*) AS mis_pedidos, MIN(id_pedido) mn FROM dbo.vw_MisPedidos; REVERT;
PRINT '--- T4 auditor ve logs pero no ventas';
EXECUTE AS USER = 'u_auditor'; SELECT TOP 3 * FROM dbo.Log_Auditoria; BEGIN TRY SELECT TOP 1 * FROM dbo.Pedido; END TRY BEGIN CATCH SELECT ERROR_MESSAGE() AS denegado; END CATCH REVERT;
PRINT '--- T5 enmascaramiento: vendedor/admin leen Cliente con DNI ofuscado o completo según UNMASK';
EXECUTE AS USER = 'u_admin'; SELECT TOP 2 id_cliente, dni, email FROM dbo.Cliente; REVERT;   -- email visible por UNMASK del administrador
GO
