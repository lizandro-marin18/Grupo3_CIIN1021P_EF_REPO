# -*- coding: utf-8 -*-
"""
simular_carga_sql.py
Réplica en Python de las reglas de sp_CargaMasivaPedidos / sp_CargaMasivaClientes (01_Automatizacion/03_Procedimientos.sql).
Sirve para (a) contar los problemas de calidad de los CSV crudos con evidencia reproducible y
(b) regenerar la carpeta Export_SQL/ cuando no se dispone de la instancia SQL Server.
Con SQL Server disponible, Export_SQL/ se obtiene con bcp (01_Automatizacion/08_Export_CSV_para_DW.sql).

Reglas (idénticas al T-SQL):
  R1 duplicados exactos / PK repetida       -> se descartan (ROW_NUMBER) y se registran
  R2 id_cliente NULL                        -> 9999 "Cliente de paso"                (Supuesto S1)
  R3 fecha_pedido no convertible a dd/mm/yyyy -> fecha de carga (2026-09-28) + fecha_imputada=1  (Supuesto S2)
  R4 monto_total <= 0                       -> rechazado (trigger trg_ValidarMontoPedido) a Log_Errores
  R5 DNI de cliente con longitud != 8       -> dni = NULL, cliente se conserva (fn_ValidarDNI)
  R6 detalle huérfano (pedido rechazado)    -> rechazado a Log_Errores
"""
import pandas as pd, numpy as np, os, json
BASE = os.path.dirname(os.path.abspath(__file__))
CR, EXD, OUT = f"{BASE}/Crudos", f"{BASE}/Externos", f"{BASE}/Export_SQL"
FECHA_CARGA = pd.Timestamp("2026-09-28")
log = []; err = []

def rd(n): return pd.read_csv(f"{CR}/{n}", encoding="utf-8-sig")

# ---------- Clientes
c = rd("Clientes_Cevicheria.csv"); n0 = len(c)
d = c.duplicated().sum(); c = c.drop_duplicates("id_cliente")
log.append(("Cliente", "R1 duplicados descartados", int(n0-len(c))))
c["dni"] = c["dni"].astype(str)
bad = c["dni"].str.len() != 8
log.append(("Cliente", "R5 DNI inválido -> NULL", int(bad.sum())))
c.loc[bad, "dni"] = np.nan
log.append(("Cliente", "email nulo (permitido)", int(c.email.isna().sum())))
paso = pd.DataFrame([{"id_cliente": 9999, "dni": np.nan, "nombre": "CLIENTE", "apellido": "DE PASO", "distrito": "N/A",
                      "tipo_cliente": "Nuevo", "fecha_registro": "01/06/2025", "email": np.nan, "telefono": np.nan}])
c = pd.concat([c, paso], ignore_index=True)
c["fecha_registro"] = pd.to_datetime(c.fecha_registro, format="%d/%m/%Y").dt.strftime("%Y-%m-%d")

# ---------- Personal / Platos (maestros)
p = rd("Personal_Cevicheria.csv"); pl = rd("Platos_Cevicheria.csv")
log.append(("Empleado", "salario_mensual nulo (permitido, S3)", int(p.salario_mensual.isna().sum())))

# ---------- Pedidos
o = rd("Pedidos_Cevicheria.csv"); n0 = len(o)
o = o.drop_duplicates("id_pedido"); log.append(("Pedido", "R1 duplicados descartados", int(n0-len(o))))
nulo_cli = int(o.id_cliente.isna().sum()); log.append(("Pedido", "R2 id_cliente NULL -> 9999", nulo_cli))
o["id_cliente"] = o.id_cliente.fillna(9999).astype(int)
f = pd.to_datetime(o.fecha_pedido, format="%d/%m/%Y", errors="coerce")
o["fecha_imputada"] = f.isna().astype(int); log.append(("Pedido", "R3 fecha inválida -> fecha de carga", int(f.isna().sum())))
o["fecha_pedido"] = f.fillna(FECHA_CARGA).dt.strftime("%Y-%m-%d")
mal = o.monto_total <= 0
for _, r in o[mal].iterrows():
    err.append(dict(tabla="Pedido", id_registro=int(r.id_pedido), motivo="monto_total <= 0 (trigger trg_ValidarMontoPedido)", valor=r.monto_total))
log.append(("Pedido", "R4 monto <= 0 rechazado", int(mal.sum())))
o_ok = o[~mal].copy()

# ---------- Detalle
dt = rd("Detalle_Pedido_Cevicheria.csv")
huer = ~dt.id_pedido.isin(o_ok.id_pedido)
for _, r in dt[huer].iterrows():
    err.append(dict(tabla="Detalle_Pedido", id_registro=int(r.id_detalle), motivo="pedido padre rechazado (huérfano)", valor=r.subtotal))
log.append(("Detalle_Pedido", "R6 huérfanos rechazados", int(huer.sum())))
dt_ok = dt[~huer]

# ---------- Asistencia
a = rd("Asistencia_Personal.csv")

# ---------- salida (lo que exportaría bcp)
c.to_csv(f"{OUT}/Cliente.csv", index=False, encoding="utf-8-sig")
p.to_csv(f"{OUT}/Empleado.csv", index=False, encoding="utf-8-sig")
pl.to_csv(f"{OUT}/Plato.csv", index=False, encoding="utf-8-sig")
o_ok.to_csv(f"{OUT}/Pedido.csv", index=False, encoding="utf-8-sig")
dt_ok.to_csv(f"{OUT}/Detalle_Pedido.csv", index=False, encoding="utf-8-sig")
a.to_csv(f"{OUT}/Asistencia.csv", index=False, encoding="utf-8-sig")
pd.DataFrame(err).to_csv(f"{OUT}/Log_Errores.csv", index=False, encoding="utf-8-sig")
pd.DataFrame(log, columns=["tabla", "regla", "registros_afectados"]).to_csv(f"{OUT}/Log_Carga_Calidad.csv", index=False, encoding="utf-8-sig")

# ---------- Problemas del CSV externo (los trata el ETL, no SQL)
e = pd.read_csv(f"{EXD}/Ventas_Delivery_Apps_Externo.csv", encoding="utf-8-sig")
res = {"externo_filas": len(e), "externo_dup_order_ref": int(e.duplicated("order_ref").sum()),
       "externo_precio_nulo": int(e.precio_bruto.isna().sum()), "externo_calif_nula": int(e.calificacion.isna().sum())}
print(pd.DataFrame(log, columns=["tabla", "regla", "n"]).to_string(index=False)); print(res)
print({"pedido_ok": len(o_ok), "detalle_ok": len(dt_ok), "cliente": len(c), "errores": len(err)})
