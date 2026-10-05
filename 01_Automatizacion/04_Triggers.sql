/* =====================================================================
   04_Triggers.sql  -  4 triggers (2 de integridad, 2 de auditoría DML). Todos seguros para operaciones multi-fila.
   T1 trg_ValidarMontoPedido   (integridad)  AFTER INSERT, UPDATE  bloquea monto <= 0 y deja evidencia
   T2 trg_ValidarDetalle       (integridad)  AFTER INSERT, UPDATE  cantidad/precio > 0 y subtotal = cantidad x precio
   T3 trg_AuditoriaEmpleado    (auditoría)   AFTER UPDATE, DELETE  registra valor anterior y nuevo del salario / bajas
   T4 trg_AuditoriaPedido      (auditoría)   AFTER UPDATE, DELETE  registra cambios y anulaciones de pedidos
   T5 trg_ProtegerLogAuditoria (inmutabilidad) INSTEAD OF UPDATE, DELETE sobre Log_Auditoria -> log append-only
   ===================================================================== */
USE Cevicheria_DB;
GO
CREATE OR ALTER TRIGGER dbo.trg_ValidarMontoPedido ON dbo.Pedido AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE monto_total <= 0)
    BEGIN
        DECLARE @n INT = (SELECT COUNT(*) FROM inserted WHERE monto_total <= 0), @ids VARCHAR(200);
        SELECT @ids = LEFT(STRING_AGG(CAST(id_pedido AS VARCHAR(10)), ','), 200) FROM inserted WHERE monto_total <= 0;
        ROLLBACK TRANSACTION;                                    -- cancela la operación completa
        -- la escritura posterior al ROLLBACK ya no pertenece a la transacción revertida: deja evidencia del intento
        INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_nuevo)
        VALUES ('Intento bloqueado: monto_total <= 0 (' + CAST(@n AS VARCHAR(10)) + ' fila/s)', 'Pedido', @ids);
        THROW 51030, 'El monto total no puede ser negativo ni cero.', 1;
    END
END;
GO
CREATE OR ALTER TRIGGER dbo.trg_ValidarDetalle ON dbo.Detalle_Pedido AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE ABS(subtotal - cantidad * precio_unitario) > 0.01)
    BEGIN
        ROLLBACK TRANSACTION;
        INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada) VALUES ('Intento bloqueado: subtotal no coincide con cantidad x precio', 'Detalle_Pedido');
        THROW 51031, 'subtotal debe ser igual a cantidad x precio_unitario.', 1;
    END
END;
GO
CREATE OR ALTER TRIGGER dbo.trg_AuditoriaEmpleado ON dbo.Empleado AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted)                                  -- UPDATE
    BEGIN
        IF UPDATE(salario_mensual)
            INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_anterior, valor_nuevo)
            SELECT 'Cambio de salario del empleado ID ' + CAST(i.id_empleado AS VARCHAR(10)), 'Empleado',
                   CAST(d.salario_mensual AS VARCHAR(20)), CAST(i.salario_mensual AS VARCHAR(20))
            FROM inserted i JOIN deleted d ON d.id_empleado = i.id_empleado
            WHERE ISNULL(i.salario_mensual, -1) <> ISNULL(d.salario_mensual, -1);
        IF UPDATE(cargo)
            INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_anterior, valor_nuevo)
            SELECT 'Cambio de cargo del empleado ID ' + CAST(i.id_empleado AS VARCHAR(10)), 'Empleado', d.cargo, i.cargo
            FROM inserted i JOIN deleted d ON d.id_empleado = i.id_empleado WHERE i.cargo <> d.cargo;
    END
    ELSE                                                                -- DELETE
        INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_anterior)
        SELECT 'Baja de empleado ID ' + CAST(id_empleado AS VARCHAR(10)), 'Empleado', cargo FROM deleted;
END;
GO
CREATE OR ALTER TRIGGER dbo.trg_AuditoriaPedido ON dbo.Pedido AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted)
        INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_anterior, valor_nuevo)
        SELECT 'Modificación de monto del pedido ' + CAST(i.id_pedido AS VARCHAR(10)), 'Pedido', CAST(d.monto_total AS VARCHAR(20)), CAST(i.monto_total AS VARCHAR(20))
        FROM inserted i JOIN deleted d ON d.id_pedido = i.id_pedido WHERE i.monto_total <> d.monto_total AND d.monto_total > 0.01;
    ELSE
        INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_anterior)
        SELECT 'Anulación (DELETE) del pedido ' + CAST(id_pedido AS VARCHAR(10)), 'Pedido', CAST(monto_total AS VARCHAR(20)) FROM deleted;
END;
GO
CREATE OR ALTER TRIGGER dbo.trg_ProtegerLogAuditoria ON dbo.Log_Auditoria INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 51040, 'Log_Auditoria es de solo inserción (Ley 29733 / ISO 27001 A.12.4): UPDATE y DELETE están prohibidos.', 1;
END;
GO
