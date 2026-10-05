/* =====================================================================
   03_Procedimientos.sql  -  4 procedimientos almacenados con TRY/CATCH y control transaccional
   SP1 sp_IngresarPedido        : alta de pedido + detalle, con SAVEPOINT por línea
   SP2 sp_ActualizarSalario     : cambio de salario con validación y auditoría
   SP3 sp_CargaMasivaClientes   : BULK INSERT -> staging -> validación -> Cliente (reglas R1, R5)
   SP4 sp_CargaMasivaPedidos    : BULK INSERT -> staging -> validación -> Pedido/Detalle (reglas R1-R4, R6)
   Utilitario: usp_RegistrarError (log de excepciones)
   Regla del CATCH:  IF @@TRANCOUNT > 0 ROLLBACK  (un trigger puede haber revertido antes)
   ===================================================================== */
USE Cevicheria_DB;
GO
CREATE OR ALTER PROCEDURE dbo.usp_RegistrarError @proc SYSNAME, @tabla VARCHAR(50) = NULL, @id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Log_Errores (procedimiento, numero_error, mensaje, tabla, id_registro)
    VALUES (@proc, ERROR_NUMBER(), ERROR_MESSAGE(), @tabla, @id);
END;
GO
/* Tipo de tabla (TVP) para enviar las líneas de un pedido */
IF TYPE_ID('dbo.tvp_LineaPedido') IS NULL
    CREATE TYPE dbo.tvp_LineaPedido AS TABLE (id_detalle INT NOT NULL, id_plato INT NOT NULL, cantidad INT NOT NULL);
GO
/* ---------------- SP1 ---------------- */
CREATE OR ALTER PROCEDURE dbo.sp_IngresarPedido
    @id_pedido INT, @id_cliente INT = NULL, @id_empleado INT, @canal VARCHAR(20), @metodo_pago VARCHAR(20),
    @lineas dbo.tvp_LineaPedido READONLY            -- (id_detalle, id_plato, cantidad)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT OFF;
    DECLARE @id_det INT, @id_plato INT, @cant INT, @pu DECIMAL(10,2), @total DECIMAL(10,2) = 0, @sp VARCHAR(20);
    BEGIN TRY
        BEGIN TRANSACTION;
        SET @id_cliente = ISNULL(@id_cliente, 9999);                          -- S1: cliente de paso
        INSERT INTO dbo.Pedido (id_pedido, fecha_pedido, hora_pedido, id_cliente, id_empleado, canal_interno, metodo_pago, monto_total)
        VALUES (@id_pedido, CAST(SYSDATETIME() AS DATE), CAST(SYSDATETIME() AS TIME(0)), @id_cliente, @id_empleado, @canal, @metodo_pago, 0.01);
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT id_detalle, id_plato, cantidad FROM @lineas;
        OPEN cur; FETCH NEXT FROM cur INTO @id_det, @id_plato, @cant;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sp = 'linea_' + CAST(@id_det AS VARCHAR(10));
            SAVE TRANSACTION @sp;                                              -- SAVEPOINT por línea
            BEGIN TRY
                SELECT @pu = precio_base FROM dbo.Plato WHERE id_plato = @id_plato;
                IF @pu IS NULL THROW 51001, 'Plato inexistente', 1;
                INSERT INTO dbo.Detalle_Pedido VALUES (@id_det, @id_pedido, @id_plato, @cant, @pu, @cant * @pu);
                SET @total += @cant * @pu;
            END TRY
            BEGIN CATCH
                ROLLBACK TRANSACTION @sp;                                      -- solo se revierte la línea defectuosa
                EXEC dbo.usp_RegistrarError 'sp_IngresarPedido', 'Detalle_Pedido', @id_det;
            END CATCH
            FETCH NEXT FROM cur INTO @id_det, @id_plato, @cant;
        END
        CLOSE cur; DEALLOCATE cur;
        IF @total <= 0 THROW 51002, 'El pedido no tiene líneas válidas', 1;
        UPDATE dbo.Pedido SET monto_total = @total WHERE id_pedido = @id_pedido;
        COMMIT TRANSACTION;
        SELECT 'OK' AS resultado, @id_pedido AS id_pedido, @total AS monto_total;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC dbo.usp_RegistrarError 'sp_IngresarPedido', 'Pedido', @id_pedido;
        SELECT 'ERROR' AS resultado, ERROR_NUMBER() AS numero_error, ERROR_MESSAGE() AS mensaje;
    END CATCH
END;
GO
/* ---------------- SP2 ---------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarSalario @id_empleado INT, @nuevo_salario DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @filas INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_empleado) THROW 51010, 'Empleado inexistente', 1;
        IF @nuevo_salario IS NULL OR @nuevo_salario < 1130.00 THROW 51011, 'Salario menor a la RMV vigente (S/ 1 130) o nulo', 1;   -- parámetro de negocio
        UPDATE dbo.Empleado SET salario_mensual = @nuevo_salario WHERE id_empleado = @id_empleado;   -- el trigger trg_AuditoriaEmpleado registra el cambio
        SET @filas = @@ROWCOUNT;                                                                       -- capturar antes del COMMIT (COMMIT reinicia @@ROWCOUNT)
        COMMIT TRANSACTION;
        SELECT 'OK' AS resultado, @filas AS filas_afectadas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC dbo.usp_RegistrarError 'sp_ActualizarSalario', 'Empleado', @id_empleado;
        SELECT 'ERROR' AS resultado, ERROR_MESSAGE() AS mensaje;
    END CATCH
END;
GO
/* ---------------- SP3 ---------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CargaMasivaClientes @ruta VARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @dup INT, @dniInv INT, @ins INT;
    BEGIN TRY
        TRUNCATE TABLE dbo.stg_Cliente;
        DECLARE @sql NVARCHAR(MAX) = N'BULK INSERT dbo.stg_Cliente FROM ''' + REPLACE(@ruta,'''','''''') +
            N''' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'', TABLOCK);';
        EXEC sys.sp_executesql @sql;
        BEGIN TRANSACTION;
        ;WITH x AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY id_cliente ORDER BY (SELECT 1)) AS rn FROM dbo.stg_Cliente)
        SELECT id_cliente, dni, nombre, apellido, distrito, tipo_cliente, fecha_registro, email, telefono, rn INTO #c FROM x;
        SELECT @dup = COUNT(*) FROM #c WHERE rn > 1;                                                        -- R1
        SELECT @dniInv = COUNT(*) FROM #c WHERE rn = 1 AND dbo.fn_ValidarDNI(dni) = 0;                    -- R5
        INSERT INTO dbo.Cliente (id_cliente, dni, nombre, apellido, email, telefono, distrito, tipo_cliente, fecha_registro)
        SELECT TRY_CAST(id_cliente AS INT), CASE WHEN dbo.fn_ValidarDNI(dni) = 1 THEN dni END, nombre, apellido, NULLIF(email,''), NULLIF(telefono,''),
               distrito, tipo_cliente, TRY_CONVERT(DATE, fecha_registro, 103)
        FROM #c WHERE rn = 1 AND TRY_CAST(id_cliente AS INT) IS NOT NULL;
        SET @ins = @@ROWCOUNT;
        IF NOT EXISTS (SELECT 1 FROM dbo.Cliente WHERE id_cliente = 9999)
            INSERT INTO dbo.Cliente (id_cliente, nombre, apellido, distrito, tipo_cliente, fecha_registro) VALUES (9999, 'CLIENTE', 'DE PASO', 'N/A', 'Nuevo', '2025-06-01');
        COMMIT TRANSACTION;
        INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_nuevo)
        VALUES ('Carga masiva clientes: insertados=' + CAST(@ins AS VARCHAR) + ', duplicados=' + CAST(@dup AS VARCHAR) + ', DNI inválidos=' + CAST(@dniInv AS VARCHAR), 'Cliente', @ruta);
        SELECT @ins AS insertados, @dup AS duplicados_descartados, @dniInv AS dni_invalidos_a_null;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC dbo.usp_RegistrarError 'sp_CargaMasivaClientes', 'Cliente', NULL;
        THROW;
    END CATCH
END;
GO
/* ---------------- SP4 ---------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CargaMasivaPedidos @ruta_pedidos VARCHAR(260), @ruta_detalle VARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @dup INT, @nulos INT, @fechaInv INT, @montoInv INT, @huer INT, @insP INT, @insD INT;
    DECLARE @hoy DATE = CAST(SYSDATETIME() AS DATE);
    BEGIN TRY
        TRUNCATE TABLE dbo.stg_Pedido; TRUNCATE TABLE dbo.stg_Detalle;
        DECLARE @s1 NVARCHAR(MAX) = N'BULK INSERT dbo.stg_Pedido FROM ''' + @ruta_pedidos + N''' WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''0x0a'', CODEPAGE=''65001'', TABLOCK);';
        DECLARE @s2 NVARCHAR(MAX) = N'BULK INSERT dbo.stg_Detalle FROM ''' + @ruta_detalle + N''' WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''0x0a'', CODEPAGE=''65001'', TABLOCK);';
        EXEC sys.sp_executesql @s1; EXEC sys.sp_executesql @s2;

        BEGIN TRANSACTION;
        SAVE TRANSACTION sv_pedidos;                                                                           -- SAVEPOINT 1
        ;WITH x AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY id_pedido ORDER BY (SELECT 1)) rn FROM dbo.stg_Pedido)
        SELECT TRY_CAST(id_pedido AS INT) id_pedido, TRY_CONVERT(DATE, fecha_pedido, 103) fecha, TRY_CAST(hora_pedido AS TIME(0)) hora,
               ISNULL(TRY_CAST(NULLIF(id_cliente,'') AS INT), 9999) id_cliente, TRY_CAST(id_empleado AS INT) id_empleado, canal_interno, metodo_pago,
               TRY_CAST(monto_total AS DECIMAL(10,2)) monto, rn, CASE WHEN NULLIF(id_cliente,'') IS NULL THEN 1 ELSE 0 END es_paso
        INTO #p FROM x;
        SELECT @dup = COUNT(*) FROM #p WHERE rn > 1;                                                            -- R1
        SELECT @nulos = COUNT(*) FROM #p WHERE rn = 1 AND es_paso = 1;                                          -- R2
        SELECT @fechaInv = COUNT(*) FROM #p WHERE rn = 1 AND fecha IS NULL;                                      -- R3
        SELECT @montoInv = COUNT(*) FROM #p WHERE rn = 1 AND (monto IS NULL OR monto <= 0);                     -- R4
        INSERT INTO dbo.Log_Errores (procedimiento, numero_error, mensaje, tabla, id_registro)
        SELECT 'sp_CargaMasivaPedidos', 51020, 'monto_total <= 0 o no numérico: pedido rechazado', 'Pedido', id_pedido FROM #p WHERE rn = 1 AND (monto IS NULL OR monto <= 0);

        SAVE TRANSACTION sv_insert;                                                                             -- SAVEPOINT 2
        BEGIN TRY
            INSERT INTO dbo.Pedido (id_pedido, fecha_pedido, hora_pedido, id_cliente, id_empleado, canal_interno, metodo_pago, monto_total, fecha_imputada)
            SELECT id_pedido, ISNULL(fecha, @hoy), hora, id_cliente, id_empleado, canal_interno, metodo_pago, monto, CASE WHEN fecha IS NULL THEN 1 ELSE 0 END   -- R3 / S2
            FROM #p WHERE rn = 1 AND monto > 0;
            SET @insP = @@ROWCOUNT;
        END TRY
        BEGIN CATCH
            ROLLBACK TRANSACTION sv_insert;                                                                     -- deshace solo la inserción
            EXEC dbo.usp_RegistrarError 'sp_CargaMasivaPedidos', 'Pedido', NULL;
            THROW;
        END CATCH

        SELECT @huer = COUNT(*) FROM dbo.stg_Detalle s WHERE NOT EXISTS (SELECT 1 FROM dbo.Pedido p WHERE p.id_pedido = TRY_CAST(s.id_pedido AS INT));   -- R6
        INSERT INTO dbo.Log_Errores (procedimiento, numero_error, mensaje, tabla, id_registro)
        SELECT 'sp_CargaMasivaPedidos', 51021, 'detalle huérfano: pedido padre rechazado', 'Detalle_Pedido', TRY_CAST(id_detalle AS INT)
        FROM dbo.stg_Detalle s WHERE NOT EXISTS (SELECT 1 FROM dbo.Pedido p WHERE p.id_pedido = TRY_CAST(s.id_pedido AS INT));
        INSERT INTO dbo.Detalle_Pedido (id_detalle, id_pedido, id_plato, cantidad, precio_unitario, subtotal)
        SELECT TRY_CAST(id_detalle AS INT), TRY_CAST(id_pedido AS INT), TRY_CAST(id_plato AS INT), TRY_CAST(cantidad AS INT),
               TRY_CAST(precio_unitario AS DECIMAL(10,2)), TRY_CAST(subtotal AS DECIMAL(10,2))
        FROM dbo.stg_Detalle s WHERE EXISTS (SELECT 1 FROM dbo.Pedido p WHERE p.id_pedido = TRY_CAST(s.id_pedido AS INT));
        SET @insD = @@ROWCOUNT;
        COMMIT TRANSACTION;

        INSERT INTO dbo.Log_Auditoria (accion, tabla_afectada, valor_nuevo)
        VALUES ('Carga masiva pedidos', 'Pedido',
                CONCAT('ins_pedidos=', @insP, '; ins_detalle=', @insD, '; dup=', @dup, '; cliente_paso=', @nulos, '; fecha_imputada=', @fechaInv, '; monto_rechazado=', @montoInv, '; huerfanos=', @huer));
        SELECT @insP AS pedidos_insertados, @insD AS detalles_insertados, @dup AS duplicados, @nulos AS cliente_paso_9999,
               @fechaInv AS fechas_imputadas, @montoInv AS montos_rechazados, @huer AS detalles_huerfanos;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC dbo.usp_RegistrarError 'sp_CargaMasivaPedidos', 'Pedido', NULL;
        THROW;
    END CATCH
END;
GO
