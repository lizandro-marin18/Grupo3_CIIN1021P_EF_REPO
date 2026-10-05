/* =====================================================================
   01_BaseDatos.sql  -  Esquema relacional de Cevicheria_DB (SQL Server)
   Proyecto integrador CIIN1021P | Cevichería "La Esquina" | Grupo 3
   Supuestos: S1 clientes nulos -> 9999 | S2 fechas inválidas -> fecha de carga | S3 salario NULL permitido
   ===================================================================== */
CREATE DATABASE Cevicheria_DB;
GO
USE Cevicheria_DB;
GO
/* ---------- Tablas maestras ---------- */
CREATE TABLE dbo.Cliente (
    id_cliente     INT           NOT NULL CONSTRAINT PK_Cliente PRIMARY KEY,
    dni            CHAR(8)       NULL,                       
    nombre         VARCHAR(50)   NOT NULL,
    apellido       VARCHAR(80)   NOT NULL,
    email          VARCHAR(100)  NULL,
    telefono       VARCHAR(15)   NULL,
    distrito       VARCHAR(40)   NULL,
    tipo_cliente   VARCHAR(25)   NOT NULL CONSTRAINT CK_Cliente_Tipo CHECK (tipo_cliente IN ('Nuevo','Frecuente','Corporativo')),
    fecha_registro DATE          NOT NULL,
    usuario_bd     SYSNAME       NULL                        
);
CREATE TABLE dbo.Empleado (
    id_empleado     INT           NOT NULL CONSTRAINT PK_Empleado PRIMARY KEY,
    dni_empleado    CHAR(8)       NOT NULL,
    nombre          VARCHAR(50)   NOT NULL,
    apellido        VARCHAR(50)   NOT NULL,
    cargo           VARCHAR(30)   NOT NULL CONSTRAINT CK_Empleado_Cargo CHECK (cargo IN ('Administrador','Cajero','Mozo','Vendedor','Cocinero','Ayudante','Delivery')),
    salario_mensual DECIMAL(10,2) NULL,                      
    usuario_bd      SYSNAME       NULL
);
CREATE TABLE dbo.Plato (
    id_plato        INT           NOT NULL CONSTRAINT PK_Plato PRIMARY KEY,
    nombre_plato    VARCHAR(100)  NOT NULL CONSTRAINT UQ_Plato_Nombre UNIQUE,
    categoria       VARCHAR(30)   NOT NULL,
    precio_base     DECIMAL(10,2) NOT NULL CONSTRAINT CK_Plato_Precio CHECK (precio_base > 0),
    costo_estimado  DECIMAL(10,2) NOT NULL CONSTRAINT CK_Plato_Costo CHECK (costo_estimado >= 0)
);
/* ---------- Tablas transaccionales ---------- */
CREATE TABLE dbo.Pedido (
    id_pedido      INT           NOT NULL CONSTRAINT PK_Pedido PRIMARY KEY,
    fecha_pedido   DATE          NOT NULL,
    hora_pedido    TIME(0)       NULL,
    id_cliente     INT           NOT NULL CONSTRAINT FK_Pedido_Cliente  REFERENCES dbo.Cliente(id_cliente),   -- 9999 = cliente de paso
    id_empleado    INT           NOT NULL CONSTRAINT FK_Pedido_Empleado REFERENCES dbo.Empleado(id_empleado),
    canal_interno  VARCHAR(20)   NOT NULL CONSTRAINT CK_Pedido_Canal CHECK (canal_interno IN ('Salón','Para llevar','Delivery propio')),
    metodo_pago    VARCHAR(20)   NOT NULL CONSTRAINT CK_Pedido_Pago  CHECK (metodo_pago IN ('Efectivo','Yape','Plin','Tarjeta')),
    monto_total    DECIMAL(10,2) NOT NULL,                   -- regla > 0 la impone el trigger trg_ValidarMontoPedido
    fecha_imputada BIT           NOT NULL CONSTRAINT DF_Pedido_Imp DEFAULT 0
);
CREATE TABLE dbo.Detalle_Pedido (
    id_detalle      INT           NOT NULL CONSTRAINT PK_Detalle PRIMARY KEY,
    id_pedido       INT           NOT NULL CONSTRAINT FK_Detalle_Pedido REFERENCES dbo.Pedido(id_pedido) ON DELETE CASCADE,
    id_plato        INT           NOT NULL CONSTRAINT FK_Detalle_Plato  REFERENCES dbo.Plato(id_plato),
    cantidad        INT           NOT NULL CONSTRAINT CK_Detalle_Cant CHECK (cantidad > 0),
    precio_unitario DECIMAL(10,2) NOT NULL CONSTRAINT CK_Detalle_PU   CHECK (precio_unitario > 0),
    subtotal        DECIMAL(10,2) NOT NULL
);
CREATE TABLE dbo.Asistencia (
    id_asistencia    INT           NOT NULL CONSTRAINT PK_Asistencia PRIMARY KEY,
    id_empleado      INT           NOT NULL CONSTRAINT FK_Asist_Emp REFERENCES dbo.Empleado(id_empleado),
    fecha            DATE          NOT NULL,
    hora_ingreso     TIME(0)       NULL,
    horas_trabajadas DECIMAL(5,2)  NULL,
    tardanza_min     INT           NOT NULL CONSTRAINT DF_Asist_Tard DEFAULT 0
);
/* ---------- Auditoría y errores ( ver trigger trg_ProtegerLogAuditoria) ---------- */
CREATE TABLE dbo.Log_Auditoria (
    id_log         INT IDENTITY(1,1) CONSTRAINT PK_LogAud PRIMARY KEY,
    fecha_hora     DATETIME2(0)  NOT NULL CONSTRAINT DF_LogAud_F DEFAULT SYSDATETIME(),
    usuario        SYSNAME       NOT NULL CONSTRAINT DF_LogAud_U DEFAULT ORIGINAL_LOGIN(),
    accion         VARCHAR(255)  NOT NULL,
    tabla_afectada VARCHAR(50)   NOT NULL,
    valor_anterior VARCHAR(255)  NULL,
    valor_nuevo    VARCHAR(255)  NULL
);
CREATE TABLE dbo.Log_Errores (
    id_error      INT IDENTITY(1,1) CONSTRAINT PK_LogErr PRIMARY KEY,
    fecha_hora    DATETIME2(0)  NOT NULL CONSTRAINT DF_LogErr_F DEFAULT SYSDATETIME(),
    procedimiento SYSNAME       NULL,
    numero_error  INT           NULL,
    mensaje       NVARCHAR(4000) NULL,
    tabla         VARCHAR(50)   NULL,
    id_registro   INT           NULL
);
/* ---------- Tablas de paso (staging) para la carga masiva de los CSV crudos ---------- */
CREATE TABLE dbo.stg_Pedido (id_pedido VARCHAR(20), fecha_pedido VARCHAR(30), hora_pedido VARCHAR(10), id_cliente VARCHAR(20),
    id_empleado VARCHAR(20), canal_interno VARCHAR(30), metodo_pago VARCHAR(30), monto_total VARCHAR(30));
CREATE TABLE dbo.stg_Detalle (id_detalle VARCHAR(20), id_pedido VARCHAR(20), id_plato VARCHAR(20), cantidad VARCHAR(20),
    precio_unitario VARCHAR(30), subtotal VARCHAR(30));
CREATE TABLE dbo.stg_Cliente (id_cliente VARCHAR(20), dni VARCHAR(20), nombre VARCHAR(60), apellido VARCHAR(90), distrito VARCHAR(40),
    tipo_cliente VARCHAR(30), fecha_registro VARCHAR(20), email VARCHAR(100), telefono VARCHAR(20));
GO
/* Índices de apoyo a FK y a las consultas críticas (ver 06_Indices_Rendimiento.sql para el análisis antes/después) */
CREATE NONCLUSTERED INDEX IX_Pedido_Cliente  ON dbo.Pedido(id_cliente);
CREATE NONCLUSTERED INDEX IX_Detalle_Pedido  ON dbo.Detalle_Pedido(id_pedido) INCLUDE (id_plato, cantidad, subtotal);
GO
