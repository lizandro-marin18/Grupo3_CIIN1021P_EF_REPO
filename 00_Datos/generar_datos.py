# -*- coding: utf-8 -*-
"""
generar_datos.py  -  Generador reproducible de datos simulados (semilla fija)
Cevichería "La Esquina" (Cajamarca)  |  CIIN1021P - Grupo 3

Produce en ./Crudos  (datos "sucios", tal como llegarían al proceso de carga):
    Clientes_Cevicheria.csv       (>5 000 filas)
    Personal_Cevicheria.csv       (25 filas: maestro; se conservan los 15 registros del EP)
    Platos_Cevicheria.csv         (40 filas: maestro/carta)
    Pedidos_Cevicheria.csv        (12 000 filas)
    Detalle_Pedido_Cevicheria.csv (~30 000 filas)
    Asistencia_Personal.csv       (6 000 filas)
y en ./Externos (fuentes ajenas a la BD relacional):
    Ventas_Delivery_Apps_Externo.csv (5 400 filas)  <- CSV externo integrado en el ETL y en Spark
    Resenas_Clientes.json / .jsonl   (5 200 docs)   <- semiestructurado (MongoDB + Spark)
    Feriados_Peru_2026.csv                          <- tabla de referencia
Se inyectan problemas de calidad de forma controlada para que el conteo del informe sea verificable.
"""
import numpy as np, pandas as pd, json, os

rng = np.random.default_rng(20260929)
BASE = os.path.dirname(os.path.abspath(__file__))
CR, EX = os.path.join(BASE, "Crudos"), os.path.join(BASE, "Externos")
os.makedirs(CR, exist_ok=True); os.makedirs(EX, exist_ok=True)

# ------------------------------------------------------------ Carta (Platos)
carta = [
 ("Ceviche Clásico","Ceviches",28),("Ceviche Mixto","Ceviches",34),("Ceviche de Conchas Negras","Ceviches",42),
 ("Ceviche de Pota","Ceviches",22),("Ceviche Carretillero","Ceviches",30),("Ceviche de Camarón","Ceviches",38),
 ("Tiradito Nikkei","Ceviches",36),("Ceviche Vegetariano","Ceviches",24),
 ("Arroz con Mariscos","Arroces",35),("Arroz Chaufa de Mariscos","Arroces",32),("Arroz con Pato Marino","Arroces",33),
 ("Arroz Negro","Arroces",36),("Chaufa de Pescado","Arroces",28),
 ("Jalea Mixta","Frituras",45),("Chicharrón de Pescado","Frituras",30),("Chicharrón de Calamar","Frituras",32),
 ("Choritos a la Chalaca","Entradas",26),("Pulpo al Olivo","Entradas",38),("Causa Limeña","Entradas",18),
 ("Papa a la Huancaína","Entradas",16),("Tequeños de Mariscos","Entradas",20),("Ensalada Marina","Entradas",22),
 ("Leche de Tigre","Leches",18),("Leche de Tigre Especial","Leches",24),("Leche de Pantera","Leches",26),
 ("Parihuela","Sopas",42),("Sopa Chilcano de Pescado","Sopas",25),("Sudado de Pescado","Sopas",34),
 ("Pescado a lo Macho","Platos Calientes",44),("Filete a la Chorrillana","Platos Calientes",38),
 ("Saltado de Mariscos","Platos Calientes",36),("Tacu Tacu con Mariscos","Platos Calientes",37),
 ("Chicha Morada (jarra)","Bebidas",14),("Limonada Frozen","Bebidas",10),("Cerveza Cusqueña","Bebidas",9),
 ("Inca Kola 500ml","Bebidas",6),("Maracuyá Sour","Bebidas",18),
 ("Suspiro Limeño","Postres",12),("Mazamorra Morada","Postres",8),("Helado de Lúcuma","Postres",10)]
platos = pd.DataFrame(carta, columns=["nombre_plato","categoria","precio_base"])
platos.insert(0, "id_plato", range(1, len(platos)+1))
platos["costo_estimado"] = (platos.precio_base*rng.uniform(0.28, 0.42, len(platos))).round(2)
pop = {"Ceviches":3.2,"Arroces":2.0,"Frituras":1.7,"Entradas":1.2,"Leches":1.6,"Sopas":1.0,
       "Platos Calientes":1.2,"Bebidas":1.8,"Postres":0.7}
platos["peso"] = platos.categoria.map(pop)*rng.uniform(0.6, 1.4, len(platos))
platos.drop(columns="peso").to_csv(f"{CR}/Platos_Cevicheria.csv", index=False, encoding="utf-8-sig")

# ------------------------------------------------------------ Personal (15 del EP + 10 nuevos)
ep_path = "/tmp/personal_ep.csv"
pers = pd.read_csv(ep_path if os.path.exists(ep_path) else os.path.join(CR, "Personal_Cevicheria.csv"))
pers = pers.iloc[:15].copy()
nuevos = [("Rosa","Quispe","Vendedor"),("Luis","Cabrera","Vendedor"),("Milagros","Tello","Vendedor"),
          ("Jhon","Chávez","Vendedor"),("Karen","Bardales","Mozo"),("Pedro","Sánchez","Delivery"),
          ("Diana","Huamán","Cajero"),("Óscar","Mendoza","Cocinero"),("Lucía","Terrones","Vendedor"),
          ("Iván","Rojas","Delivery")]
sal = {"Vendedor":1500,"Mozo":1400,"Delivery":1300,"Cajero":1650,"Cocinero":2200}
filas = []
for k, (n, a, c) in enumerate(nuevos, start=16):
    filas.append(dict(id_empleado=k, dni_empleado=int(rng.integers(20000000, 79999999)), nombre=n,
                      apellido=a, cargo=c, salario_mensual=round(sal[c]*rng.uniform(0.95, 1.2), 2)))
pers = pd.concat([pers, pd.DataFrame(filas)], ignore_index=True)
pers.to_csv(f"{CR}/Personal_Cevicheria.csv", index=False, encoding="utf-8-sig")
vendedores = pers[pers.cargo.isin(["Mozo","Cajero","Vendedor"])].id_empleado.values

# ------------------------------------------------------------ Clientes
nom = ["Juan","María","Carlos","Ana","Luis","Rosa","Jorge","Carmen","Pedro","Luz","José","Elena","Miguel","Sofía",
       "Ricardo","Patricia","Fernando","Gabriela","Andrés","Valeria","Diego","Camila","Héctor","Milagros","Wilmer",
       "Yesenia","Edwin","Noemí","Segundo","Marleni"]
ape = ["Quispe","Rojas","Mendoza","Flores","Cabrera","Chávez","Torres","Vásquez","Huamán","Tello","Sánchez","Ramos",
       "Díaz","Bardales","Terrones","Cueva","Zelada","Alva","Guevara","Aguilar","Pérez","Lozano","Castrejón","Mego",
       "Llamo","Sangay","Becerra","Coronel"]
dist = ["Cajamarca","Baños del Inca","Los Baños","Llacanora","San Juan","Namora","Jesús","Magdalena","Cajabamba","Celendín"]
dist_p = np.array([55,15,4,3,4,2,3,3,6,5], float); dist_p /= dist_p.sum()
N_CLI = 5500
cli = pd.DataFrame({
    "id_cliente": np.arange(1, N_CLI+1),
    "dni": rng.integers(10000000, 79999999, N_CLI).astype(str),
    "nombre": rng.choice(nom, N_CLI),
    "apellido": rng.choice(ape, N_CLI)+" "+rng.choice(ape, N_CLI),
    "distrito": rng.choice(dist, N_CLI, p=dist_p),
    "tipo_cliente": rng.choice(["Nuevo","Frecuente","Corporativo"], N_CLI, p=[.62,.33,.05]),
    "fecha_registro": pd.to_datetime("2025-06-01")+pd.to_timedelta(rng.integers(0, 470, N_CLI), unit="D")})
cli["email"] = (cli.nombre.str.lower().str.normalize("NFKD").str.encode("ascii","ignore").str.decode("ascii")
                + cli.id_cliente.astype(str)+"@correo.pe")
cli["telefono"] = "9"+pd.Series(rng.integers(10000000, 99999999, N_CLI)).astype(str)
cli["fecha_registro"] = cli.fecha_registro.dt.strftime("%d/%m/%Y")
bad_email = rng.choice(N_CLI, 165, replace=False); cli.loc[bad_email, "email"] = np.nan
bad_dni = rng.choice(N_CLI, 32, replace=False); cli.loc[bad_dni, "dni"] = cli.loc[bad_dni, "dni"].str[:7]
dups = cli.sample(45, random_state=3)
pd.concat([cli, dups]).reset_index(drop=True).to_csv(f"{CR}/Clientes_Cevicheria.csv", index=False, encoding="utf-8-sig")

# ------------------------------------------------------------ Pedidos + Detalle
N_PED = 12000
d0, d1 = pd.Timestamp("2025-10-01"), pd.Timestamp("2026-09-27")
dias = pd.date_range(d0, d1)
wd = np.array([0.8,0.8,0.85,0.9,1.25,1.6,1.9])[dias.dayofweek]
trend = np.linspace(0.85, 1.25, len(dias)); season = np.where(dias.month.isin([12,1,2,3]), 1.15, 1.0)
w = wd*trend*season; w /= w.sum()
fechas = np.sort(rng.choice(dias, N_PED, p=w))
h = rng.choice([11,12,13,14,15,16,17,18,19,20,21], N_PED, p=[.05,.11,.17,.16,.09,.05,.05,.08,.11,.09,.04])
hora = [f"{a:02d}:{rng.integers(0,60):02d}" for a in h]
canal_i = rng.choice(["Salón","Para llevar","Delivery propio"], N_PED, p=[.62,.20,.18])
pago = rng.choice(["Efectivo","Yape","Plin","Tarjeta"], N_PED, p=[.34,.31,.12,.23])
pes = rng.pareto(2.2, N_CLI)+1; pes /= pes.sum()
id_cli = rng.choice(np.arange(1, N_CLI+1), N_PED, p=pes).astype(float)
id_cli[rng.random(N_PED) < 0.09] = np.nan
id_emp = rng.choice(vendedores, N_PED)
pp = (platos.peso/platos.peso.sum()).values
n_lin = rng.choice([1,2,3,4,5,6], N_PED, p=[.12,.30,.28,.16,.09,.05])
precio = platos.set_index("id_plato").precio_base.to_dict()
det = []; did = 1; tot = np.zeros(N_PED)
for i, k in enumerate(n_lin):
    ids = rng.choice(platos.id_plato.values, size=k, replace=False, p=pp)
    for j in ids:
        q = int(rng.choice([1,2,3], p=[.62,.28,.10])); pu = float(precio[int(j)])
        det.append((did, i+1, int(j), q, pu, round(q*pu, 2))); tot[i] += q*pu; did += 1
detalle = pd.DataFrame(det, columns=["id_detalle","id_pedido","id_plato","cantidad","precio_unitario","subtotal"])
ped = pd.DataFrame({"id_pedido": np.arange(1, N_PED+1), "fecha_pedido": pd.to_datetime(fechas).strftime("%d/%m/%Y"),
                    "hora_pedido": hora, "id_cliente": id_cli, "id_empleado": id_emp, "canal_interno": canal_i,
                    "metodo_pago": pago, "monto_total": np.round(tot, 2)})
ped["id_cliente"] = ped.id_cliente.astype("Int64")
idx = rng.permutation(N_PED)
ped.loc[idx[:52], "fecha_pedido"] = "Ayer"
ped.loc[idx[52:78], "fecha_pedido"] = "No se sabe"
neg = idx[100:118]
ped.loc[neg[:12], "monto_total"] = -ped.loc[neg[:12], "monto_total"]
ped.loc[neg[12:], "monto_total"] = 0
pd.concat([ped, ped.sample(38, random_state=5)]).reset_index(drop=True).to_csv(
    f"{CR}/Pedidos_Cevicheria.csv", index=False, encoding="utf-8-sig")
detalle.to_csv(f"{CR}/Detalle_Pedido_Cevicheria.csv", index=False, encoding="utf-8-sig")

# ------------------------------------------------------------ Asistencia
N_AS = 6000
a_emp = rng.choice(pers.id_empleado.values, N_AS)
a_f = pd.to_datetime(rng.choice(dias, N_AS))
ing = rng.integers(8, 12, N_AS)*60+rng.integers(-20, 25, N_AS)
hrs = np.round(rng.normal(8.2, 1.1, N_AS).clip(4, 12), 2)
asis = pd.DataFrame({"id_asistencia": np.arange(1, N_AS+1), "id_empleado": a_emp, "fecha": a_f.strftime("%Y-%m-%d"),
                     "hora_ingreso": [f"{m//60:02d}:{m%60:02d}" for m in ing], "horas_trabajadas": hrs})
asis["tardanza_min"] = np.where(rng.random(N_AS) < 0.18, rng.integers(3, 40, N_AS), 0)
asis.to_csv(f"{CR}/Asistencia_Personal.csv", index=False, encoding="utf-8-sig")

# ------------------------------------------------------------ Externo: delivery apps
N_EX = 5400
def variantes(n):
    sin = n
    for a, b in zip("áéíóú", "aeiou"):
        sin = sin.replace(a, b)
    return [n, n.lower(), n.upper(), n.replace("Ceviche", "Cebiche"), sin]
top = platos[platos.categoria.isin(["Ceviches","Arroces","Frituras","Leches","Platos Calientes","Sopas"])]
e_pl = rng.choice(top.nombre_plato.values, N_EX, p=(top.peso/top.peso.sum()).values)
e_nom = [variantes(x)[rng.integers(0, 5)] for x in e_pl]
e_fecha = pd.to_datetime(rng.choice(pd.date_range("2026-01-01", d1), N_EX))
e_q = rng.choice([1,2,3], N_EX, p=[.7,.22,.08])
e_pu = platos.set_index("nombre_plato").loc[e_pl, "precio_base"].values
plat = rng.choice(["PedidosYa","Rappi"], N_EX, p=[.58,.42])
ext = pd.DataFrame({"order_ref": [f"EXT-{100000+i}" for i in range(N_EX)], "fecha_iso": e_fecha.strftime("%Y-%m-%d"),
    "plataforma": plat, "plato": e_nom, "cantidad": e_q, "precio_bruto": np.round(e_q*e_pu*1.10, 2),
    "comision_pct": np.where(plat == "PedidosYa", rng.choice([22,25], N_EX), rng.choice([18,20], N_EX)),
    "distrito_entrega": rng.choice(dist[:6], N_EX, p=[.6,.2,.06,.06,.04,.04]),
    "tiempo_entrega_min": np.clip(rng.normal(34, 9, N_EX), 12, 80).round(0).astype(int),
    "calificacion": rng.choice([1,2,3,4,5,np.nan], N_EX, p=[.03,.05,.14,.32,.32,.14])})
ext_raw = pd.concat([ext, ext.sample(60, random_state=9)]).reset_index(drop=True)
ext_raw.loc[rng.choice(len(ext_raw), 12, replace=False), "precio_bruto"] = np.nan
ext_raw.to_csv(f"{EX}/Ventas_Delivery_Apps_Externo.csv", index=False, encoding="utf-8-sig")

# ------------------------------------------------------------ Externo: reseñas (JSON semiestructurado)
pos = ["El pescado súper fresco, volveré pronto.","Excelente sazón y buena porción.","Atención rápida y el local muy limpio.",
       "El mejor {p} que he probado en Cajamarca.","Muy recomendado para ir en familia."]
neu = ["Estuvo bien, aunque tardaron un poco.","Buen sabor pero la porción pequeña.","Correcto, nada fuera de lo común."]
neg_ = ["El pedido llegó frío y demoró mucho.","Muy caro para lo que ofrecen.","El pescado no estaba tan fresco.","Mala atención del personal."]
etq = ["fresco","familiar","precio","rápido","picante","delivery","limpio","porción","atención","sabor"]
mu = platos.set_index("nombre_plato").categoria.map({"Ceviches":4.4,"Arroces":4.2,"Frituras":4.0,"Entradas":3.9,
     "Leches":4.3,"Sopas":4.1,"Platos Calientes":4.0,"Bebidas":3.8,"Postres":4.0})
docs = []
for i in range(5200):
    pl = str(rng.choice(platos.nombre_plato.values, p=(platos.peso/platos.peso.sum()).values))
    pu_ = int(np.clip(round(rng.normal(mu[pl], 0.9)), 1, 5))
    txt = str(rng.choice(pos if pu_ >= 4 else neu if pu_ == 3 else neg_)).replace("{p}", pl)
    d = {"_id": i+1, "plato": pl, "puntuacion": pu_, "comentario": txt,
         "fuente": str(rng.choice(["Google Maps","Facebook","TripAdvisor","Encuesta QR"], p=[.5,.2,.1,.2])),
         "fecha": pd.Timestamp(rng.choice(dias)).strftime("%Y-%m-%d")}
    if rng.random() < 0.55: d["id_cliente"] = int(rng.integers(1, N_CLI+1))
    if rng.random() < 0.60: d["etiquetas"] = [str(x) for x in rng.choice(etq, int(rng.integers(1, 4)), replace=False)]
    if rng.random() < 0.25: d["respuesta_local"] = "Gracias por tu opinión, ¡te esperamos!"
    if rng.random() < 0.30: d["util_votos"] = int(rng.integers(0, 40))
    if rng.random() < 0.15:
        d["visita"] = {"acompanantes": int(rng.integers(0, 8)),
                       "ocasion": str(rng.choice(["Cumpleaños","Trabajo","Familiar","Pareja"]))}
    docs.append(d)
json.dump(docs, open(f"{EX}/Resenas_Clientes.json", "w", encoding="utf-8"), ensure_ascii=False)
with open(f"{EX}/Resenas_Clientes.jsonl", "w", encoding="utf-8") as f:
    for d in docs:
        f.write(json.dumps(d, ensure_ascii=False)+"\n")

# ------------------------------------------------------------ Feriados (referencia)
fer = [("2025-11-01","Todos los Santos"),("2025-12-08","Inmaculada Concepción"),("2025-12-09","Batalla de Ayacucho"),
       ("2025-12-25","Navidad"),("2026-01-01","Año Nuevo"),("2026-04-02","Jueves Santo"),("2026-04-03","Viernes Santo"),
       ("2026-05-01","Día del Trabajo"),("2026-06-07","Batalla de Arica"),("2026-06-29","San Pedro y San Pablo"),
       ("2026-07-23","Día de la Fuerza Aérea"),("2026-07-28","Fiestas Patrias"),("2026-07-29","Fiestas Patrias"),
       ("2026-08-06","Batalla de Junín"),("2026-08-30","Santa Rosa de Lima"),("2026-10-08","Combate de Angamos"),
       ("2026-11-01","Todos los Santos"),("2026-12-08","Inmaculada Concepción"),("2026-12-09","Batalla de Ayacucho"),
       ("2026-12-25","Navidad")]
pd.DataFrame(fer, columns=["fecha","feriado"]).to_csv(f"{EX}/Feriados_Peru_2026.csv", index=False, encoding="utf-8-sig")
print({"clientes_raw": len(cli)+45, "pedidos_raw": len(ped)+38, "detalle": len(detalle), "asistencia": len(asis),
       "externo": len(ext_raw), "resenas": len(docs), "personal": len(pers), "platos": len(platos)})
