# -*- coding: utf-8 -*-
"""
etl_cevicheria.py  -  ETL (Extract-Transform-Load) con Python/pandas
Cevichería "La Esquina" | CIIN1021P Grupo 3

EXTRACT   : (1) CSV exportados desde SQL Server (bcp)  -> ../00_Datos/Export_SQL/*.csv
            (2) CSV EXTERNO de plataformas delivery    -> ../00_Datos/Externos/Ventas_Delivery_Apps_Externo.csv
            (3) Tabla de referencia de feriados        -> ../00_Datos/Externos/Feriados_Peru_2026.csv
TRANSFORM : limpieza, normalización, enriquecimiento, seudonimización (Ley 29733), llaves sustitutas
LOAD      : modelo estrella Kimball -> ./DW_csv/*.csv  y  DW_Cevicheria.db (SQLite, validación OLAP)
            (DDL SQL Server equivalente: 12_DW_DDL.sql)
Cada paso escribe en logs/etl_log.txt y logs/etl_log.csv (paso, descripción, filas_in, filas_out, afectadas).
"""
import pandas as pd, numpy as np, hashlib, os, sqlite3, time, unicodedata, datetime as dt

BASE = os.path.dirname(os.path.abspath(__file__))
SQLX = f"{BASE}/../00_Datos/Export_SQL"; EXT = f"{BASE}/../00_Datos/Externos"
OUT, LOGD = f"{BASE}/DW_csv", f"{BASE}/logs"
SALT = "LaEsquina2026"          # misma sal que vw_DW_Cliente (HASHBYTES SHA2_256) en SQL Server
steps = []; T0 = time.time()

def log(paso, desc, fin, fout, afect=0):
    steps.append(dict(paso=paso, descripcion=desc, filas_in=fin, filas_out=fout, filas_afectadas=afect,
                      marca_tiempo=dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
    print(f"[{paso}] {desc}: in={fin} out={fout} afectadas={afect}")

def sin_tildes(s):
    return "".join(c for c in unicodedata.normalize("NFKD", str(s)) if not unicodedata.combining(c))

def norm(s):
    return sin_tildes(s).lower().strip().replace("cebiche", "ceviche")

# =========================================================== EXTRACT
cli = pd.read_csv(f"{SQLX}/Cliente.csv", encoding="utf-8-sig", dtype={"dni": str})
emp = pd.read_csv(f"{SQLX}/Empleado.csv", encoding="utf-8-sig")
pla = pd.read_csv(f"{SQLX}/Plato.csv", encoding="utf-8-sig")
ped = pd.read_csv(f"{SQLX}/Pedido.csv", encoding="utf-8-sig")
det = pd.read_csv(f"{SQLX}/Detalle_Pedido.csv", encoding="utf-8-sig")
ext = pd.read_csv(f"{EXT}/Ventas_Delivery_Apps_Externo.csv", encoding="utf-8-sig")
fer = pd.read_csv(f"{EXT}/Feriados_Peru_2026.csv", encoding="utf-8-sig")
log("E01", "Extracción CSV exportados de SQL Server (Cliente, Empleado, Plato, Pedido, Detalle)", 0, len(cli)+len(emp)+len(pla)+len(ped)+len(det))
log("E02", "Extracción CSV externo delivery apps (PedidosYa/Rappi)", 0, len(ext))
log("E03", "Extracción tabla de referencia de feriados", 0, len(fer))

# =========================================================== TRANSFORM
# T01 duplicados del CSV externo (order_ref repetido)
n = len(ext); ext = ext.drop_duplicates("order_ref"); log("T01", "Eliminar duplicados por order_ref en CSV externo", n, len(ext), n-len(ext))

# T02 nulos en precio_bruto externo: imputar con precio_base * cantidad * 1.10 (recargo app)
pb = pla.set_index("nombre_plato").precio_base
mapa = {norm(x): x for x in pla.nombre_plato}
ext["plato_norm"] = ext.plato.map(lambda x: mapa.get(norm(x)))
sin_map = int(ext.plato_norm.isna().sum())
log("T02", "Normalizar nombre de plato (tildes, mayúsculas, 'cebiche'->'ceviche') contra catálogo SQL", len(ext), len(ext), int((ext.plato != ext.plato_norm).sum()))
assert sin_map == 0, "platos sin mapear"
nulos = ext.precio_bruto.isna()
ext.loc[nulos, "precio_bruto"] = (ext.loc[nulos, "plato_norm"].map(pb)*ext.loc[nulos, "cantidad"]*1.10).round(2)
log("T03", "Imputar precio_bruto nulo = precio_base x cantidad x 1.10", len(ext), len(ext), int(nulos.sum()))

# T04 tipificación de fechas
ext["fecha"] = pd.to_datetime(ext.fecha_iso, format="%Y-%m-%d")
ped["fecha"] = pd.to_datetime(ped.fecha_pedido, format="%Y-%m-%d")
log("T04", "Tipificar fechas (ISO) en Pedido y CSV externo", len(ped)+len(ext), len(ped)+len(ext), 0)

# T05 seudonimización DNI + minimización de datos (Ley 29733 Art. 7/8: proporcionalidad y calidad)
def h(x): return hashlib.sha256((SALT+str(x)).encode()).hexdigest().upper() if pd.notna(x) else None
cli["dni_hash"] = cli.dni.map(h)
log("T05", "Seudonimizar DNI (SHA-256+sal) y excluir email/teléfono/nombre/salario del DW", len(cli), len(cli), int(cli.dni_hash.notna().sum()))

# T06 enriquecimiento: turno, día semana, feriado, rango de ticket
def turno(hm):
    hh = int(str(hm)[:2])
    return "Almuerzo (11-15h)" if hh < 15 else "Tarde (15-18h)" if hh < 18 else "Noche (18-22h)"
ped["turno"] = ped.hora_pedido.map(turno)
log("T06", "Derivar turno (Almuerzo/Tarde/Noche) desde hora_pedido", len(ped), len(ped), len(ped))

# T07 verificación de integridad referencial contra dimensiones
ok_c = ped.id_cliente.isin(cli.id_cliente).all(); ok_e = ped.id_empleado.isin(emp.id_empleado).all(); ok_p = det.id_plato.isin(pla.id_plato).all()
assert ok_c and ok_e and ok_p
log("T07", "Validar integridad referencial pedido->cliente/empleado, detalle->plato", len(ped)+len(det), len(ped)+len(det), 0)

# T08 conciliación: suma de detalle = monto_total del pedido
chk = det.groupby("id_pedido").subtotal.sum().round(2).rename("suma_det")
ped = ped.merge(chk, on="id_pedido", how="left")
disc = (ped.suma_det.round(2) != ped.monto_total.round(2)).sum()
log("T08", "Conciliar SUM(detalle) = monto_total del pedido (discrepancias)", len(ped), len(ped), int(disc))

# =========================================================== DIMENSIONES
# dim_fecha
d0, d1 = pd.Timestamp("2025-10-01"), pd.Timestamp("2026-12-31")
f = pd.DataFrame({"fecha": pd.date_range(d0, d1)})
meses = ["Enero","Febrero","Marzo","Abril","Mayo","Junio","Julio","Agosto","Setiembre","Octubre","Noviembre","Diciembre"]
dias = ["Lunes","Martes","Miércoles","Jueves","Viernes","Sábado","Domingo"]
fer["fecha"] = pd.to_datetime(fer.fecha)
f["sk_fecha"] = f.fecha.dt.strftime("%Y%m%d").astype(int)
f["anio"] = f.fecha.dt.year; f["trimestre"] = f.fecha.dt.quarter; f["mes_num"] = f.fecha.dt.month
f["mes_nombre"] = f.mes_num.map(lambda m: meses[m-1]); f["anio_mes"] = f.fecha.dt.strftime("%Y-%m")
f["semana_iso"] = f.fecha.dt.isocalendar().week.astype(int); f["dia_mes"] = f.fecha.dt.day
f["dia_semana_num"] = f.fecha.dt.dayofweek+1; f["dia_semana"] = f.dia_semana_num.map(lambda d: dias[d-1])
f["es_fin_semana"] = (f.dia_semana_num >= 6).astype(int)
f = f.merge(fer.rename(columns={"feriado": "nombre_feriado"}), on="fecha", how="left")
f["es_feriado"] = f.nombre_feriado.notna().astype(int); f["nombre_feriado"] = f.nombre_feriado.fillna("")
f["fecha"] = f.fecha.dt.strftime("%Y-%m-%d")
dim_fecha = f[["sk_fecha", "fecha", "anio", "trimestre", "mes_num", "mes_nombre", "anio_mes", "semana_iso", "dia_mes",
               "dia_semana_num", "dia_semana", "es_fin_semana", "es_feriado", "nombre_feriado"]]
log("L01", "Construir Dim_Fecha (2025-10-01 a 2026-12-31) con feriados", len(fer), len(dim_fecha), int(dim_fecha.es_feriado.sum()))

# dim_cliente (SCD tipo 1) + miembros especiales
base = pd.date_range("2026-09-28", periods=1)[0]
c = cli[cli.id_cliente != 9999].copy()
c["antiguedad_meses"] = ((base - pd.to_datetime(c.fecha_registro)).dt.days/30.4).round().astype(int)
dim_cliente = pd.DataFrame({"id_cliente_nk": c.id_cliente, "cliente_seudonimo": "C-"+c.id_cliente.astype(str).str.zfill(5),
    "dni_hash": c.dni_hash, "distrito": c.distrito, "tipo_cliente": c.tipo_cliente, "fecha_registro": c.fecha_registro,
    "antiguedad_meses": c.antiguedad_meses, "es_cliente_identificado": 1})
esp = pd.DataFrame([dict(id_cliente_nk=9999, cliente_seudonimo="C-PASO", dni_hash=None, distrito="N/A", tipo_cliente="Cliente de paso",
                         fecha_registro="2025-06-01", antiguedad_meses=0, es_cliente_identificado=0),
                    dict(id_cliente_nk=9998, cliente_seudonimo="C-APP", dni_hash=None, distrito="N/A", tipo_cliente="Cliente App Delivery",
                         fecha_registro="2026-01-01", antiguedad_meses=0, es_cliente_identificado=0)])
dim_cliente = pd.concat([esp, dim_cliente], ignore_index=True); dim_cliente.insert(0, "sk_cliente", range(1, len(dim_cliente)+1))
log("L02", "Construir Dim_Cliente (SCD1, seudonimizada, 2 miembros especiales)", len(cli), len(dim_cliente), 2)

# dim_plato
dim_plato = pla.rename(columns={"id_plato": "id_plato_nk"}).copy()
dim_plato["margen_unitario"] = (dim_plato.precio_base-dim_plato.costo_estimado).round(2)
dim_plato["margen_pct"] = (dim_plato.margen_unitario/dim_plato.precio_base*100).round(1)
dim_plato["rango_precio"] = pd.cut(dim_plato.precio_base, [0, 15, 30, 40, 1000], labels=["Económico (<=15)", "Medio (16-30)", "Alto (31-40)", "Premium (>40)"]).astype(str)
dim_plato.insert(0, "sk_plato", range(1, len(dim_plato)+1))
log("L03", "Construir Dim_Plato (categoría, margen, rango de precio)", len(pla), len(dim_plato), len(dim_plato))

# dim_empleado (sin DNI ni salario)
dim_empleado = pd.DataFrame({"id_empleado_nk": emp.id_empleado, "nombre_completo": emp.nombre+" "+emp.apellido, "cargo": emp.cargo})
dim_empleado = pd.concat([pd.DataFrame([dict(id_empleado_nk=0, nombre_completo="Sin vendedor (plataforma externa)", cargo="N/A")]), dim_empleado], ignore_index=True)
dim_empleado.insert(0, "sk_empleado", range(1, len(dim_empleado)+1))
log("L04", "Construir Dim_Empleado (sin DNI ni salario: minimización de datos)", len(emp), len(dim_empleado), 1)

# dim_metodo_pago, dim_canal, dim_turno
dim_pago = pd.DataFrame({"metodo_pago": ["Efectivo", "Yape", "Plin", "Tarjeta", "Pasarela de la plataforma"],
                         "tipo_pago": ["Físico", "Billetera digital", "Billetera digital", "Tarjeta", "Plataforma"]})
dim_pago.insert(0, "sk_pago", range(1, len(dim_pago)+1))
dim_canal = pd.DataFrame({"canal": ["Salón", "Para llevar", "Delivery propio", "PedidosYa", "Rappi"],
                          "tipo_canal": ["Presencial", "Presencial", "Delivery", "Delivery (app)", "Delivery (app)"],
                          "origen_datos": ["SQL Server", "SQL Server", "SQL Server", "CSV externo", "CSV externo"]})
dim_canal.insert(0, "sk_canal", range(1, len(dim_canal)+1))
dim_turno = pd.DataFrame({"turno": ["Almuerzo (11-15h)", "Tarde (15-18h)", "Noche (18-22h)", "No registrado"]}); dim_turno.insert(0, "sk_turno", range(1, 5))
log("L05", "Construir Dim_MetodoPago, Dim_Canal, Dim_Turno", 0, len(dim_pago)+len(dim_canal)+len(dim_turno), 0)

# =========================================================== FACT (grano: línea de pedido)
SK = lambda d, nk, sk: d.set_index(nk)[sk]
sk_cli = SK(dim_cliente, "id_cliente_nk", "sk_cliente"); sk_pl = SK(dim_plato, "id_plato_nk", "sk_plato")
sk_em = SK(dim_empleado, "id_empleado_nk", "sk_empleado"); sk_pg = SK(dim_pago, "metodo_pago", "sk_pago")
sk_ca = SK(dim_canal, "canal", "sk_canal"); sk_tu = SK(dim_turno, "turno", "sk_turno")
costo = dim_plato.set_index("id_plato_nk").costo_estimado

a = det.merge(ped[["id_pedido", "fecha", "id_cliente", "id_empleado", "canal_interno", "metodo_pago", "turno"]], on="id_pedido", how="inner")
f1 = pd.DataFrame({"sk_fecha": a.fecha.dt.strftime("%Y%m%d").astype(int), "sk_cliente": a.id_cliente.map(sk_cli), "sk_plato": a.id_plato.map(sk_pl),
    "sk_empleado": a.id_empleado.map(sk_em), "sk_pago": a.metodo_pago.map(sk_pg), "sk_canal": a.canal_interno.map(sk_ca), "sk_turno": a.turno.map(sk_tu),
    "nro_pedido": "SQL-"+a.id_pedido.astype(str), "origen": "SQL Server", "cantidad": a.cantidad, "precio_unitario": a.precio_unitario,
    "importe_bruto": a.subtotal, "comision_plataforma": 0.0, "importe_neto": a.subtotal,
    "costo_total": (a.id_plato.map(costo)*a.cantidad).round(2), "tiempo_entrega_min": np.nan, "calificacion": np.nan})
pid = ext.plato_norm.map(pla.set_index("nombre_plato").id_plato)
com = (ext.precio_bruto*ext.comision_pct/100).round(2)
f2 = pd.DataFrame({"sk_fecha": ext.fecha.dt.strftime("%Y%m%d").astype(int), "sk_cliente": sk_cli[9998], "sk_plato": pid.map(sk_pl),
    "sk_empleado": sk_em[0], "sk_pago": sk_pg["Pasarela de la plataforma"], "sk_canal": ext.plataforma.map(sk_ca), "sk_turno": sk_tu["No registrado"],
    "nro_pedido": ext.order_ref, "origen": "CSV externo", "cantidad": ext.cantidad, "precio_unitario": (ext.precio_bruto/ext.cantidad).round(2),
    "importe_bruto": ext.precio_bruto, "comision_plataforma": com, "importe_neto": (ext.precio_bruto-com).round(2),
    "costo_total": (pid.map(costo)*ext.cantidad).round(2), "tiempo_entrega_min": ext.tiempo_entrega_min, "calificacion": ext.calificacion})
fact = pd.concat([f1, f2], ignore_index=True)
fact["margen_bruto"] = (fact.importe_neto-fact.costo_total).round(2)
fact.insert(0, "sk_venta", range(1, len(fact)+1))
# Enteros con NULL: sin esto pandas escribe "34.0" y BULK INSERT de SQL Server falla al convertir a INT (error 4864)
fact["tiempo_entrega_min"] = fact["tiempo_entrega_min"].astype("Int64")
log("L06", "Construir Fact_Ventas (grano = línea de pedido) integrando SQL Server + CSV externo", len(a)+len(ext), len(fact), len(f2))
assert fact.isna()[["sk_fecha", "sk_cliente", "sk_plato", "sk_empleado", "sk_pago", "sk_canal", "sk_turno"]].sum().sum() == 0
log("L07", "Verificar cero llaves sustitutas nulas en Fact_Ventas", len(fact), len(fact), 0)

# =========================================================== LOAD
tablas = dict(dim_fecha=dim_fecha, dim_cliente=dim_cliente, dim_plato=dim_plato, dim_empleado=dim_empleado,
              dim_metodo_pago=dim_pago, dim_canal=dim_canal, dim_turno=dim_turno, fact_ventas=fact)
os.makedirs(OUT, exist_ok=True); os.makedirs(LOGD, exist_ok=True)
for k, v in tablas.items(): v.to_csv(f"{OUT}/{k}.csv", index=False, encoding="utf-8", lineterminator="\n")
db = f"{BASE}/DW_Cevicheria.db"
if os.path.exists(db): os.remove(db)
cn = sqlite3.connect(db)
for k, v in tablas.items(): v.to_sql(k, cn, index=False)
cn.execute("CREATE INDEX ix_fact_fecha ON fact_ventas(sk_fecha)"); cn.execute("CREATE INDEX ix_fact_plato ON fact_ventas(sk_plato)"); cn.commit(); cn.close()
log("L08", "Cargar tablas del DW a CSV y SQLite (%s)" % ", ".join(tablas), len(fact), sum(len(v) for v in tablas.values()), len(tablas))
seg = round(time.time()-T0, 2)
log("FIN", f"ETL finalizado en {seg} s", 0, 0, 0)
lg = pd.DataFrame(steps); lg.to_csv(f"{LOGD}/etl_log.csv", index=False, encoding="utf-8", lineterminator="\n")
with open(f"{LOGD}/etl_log.txt", "w", encoding="utf-8") as fh:
    for s in steps: fh.write(f"{s['marca_tiempo']} [{s['paso']}] {s['descripcion']} | in={s['filas_in']} out={s['filas_out']} afectadas={s['filas_afectadas']}\n")
print("\nFact rows:", len(fact), "| ventas netas S/", round(fact.importe_neto.sum(), 2))
