# -*- coding: utf-8 -*-
"""
olap_kpis.py - KPIs, operaciones OLAP y vistas de referencia del dashboard, calculados sobre el Data Warehouse.
Los mismos cálculos están implementados como medidas DAX en medidas_DAX.md (Power BI) y como T-SQL en
13_OLAP_Consultas.sql (ROLLUP / CUBE / GROUPING SETS).
Salida: ./olap_resultados/*.csv  y  ./graficos/*.png
"""
import pandas as pd, numpy as np, os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

BASE = os.path.dirname(os.path.abspath(__file__)); DW = f"{BASE}/../04_DataWarehouse_ETL/DW_csv"
RES, GRA = f"{BASE}/olap_resultados", f"{BASE}/graficos"; os.makedirs(RES, exist_ok=True); os.makedirs(GRA, exist_ok=True)
F = pd.read_csv(f"{DW}/fact_ventas.csv"); DF = pd.read_csv(f"{DW}/dim_fecha.csv"); DC = pd.read_csv(f"{DW}/dim_cliente.csv")
DP = pd.read_csv(f"{DW}/dim_plato.csv"); DK = pd.read_csv(f"{DW}/dim_canal.csv"); DT = pd.read_csv(f"{DW}/dim_turno.csv")
DG = pd.read_csv(f"{DW}/dim_metodo_pago.csv"); DE = pd.read_csv(f"{DW}/dim_empleado.csv")
X = (F.merge(DF, on="sk_fecha").merge(DP, on="sk_plato").merge(DK, on="sk_canal").merge(DT, on="sk_turno")
      .merge(DG, on="sk_pago").merge(DE, on="sk_empleado").merge(DC[["sk_cliente", "id_cliente_nk", "distrito", "tipo_cliente", "es_cliente_identificado"]], on="sk_cliente"))
azul, verde, naranja, gris, rojo = "#1F3A5F", "#2A9D8F", "#E9A03B", "#8D99AE", "#C8553D"
plt.rcParams.update({"font.family": "DejaVu Sans", "axes.spines.top": False, "axes.spines.right": False, "axes.titleweight": "bold", "axes.titlesize": 11})
soles = FuncFormatter(lambda v, p: f"S/ {v/1000:,.0f}k" if v else "0")

# ------------------------------------------------------------------ KPIs
ped = X.groupby("nro_pedido").agg(neto=("importe_neto", "sum"), cliente=("id_cliente_nk", "first"), ident=("es_cliente_identificado", "first"))
ident = ped[ped.ident == 1].groupby("cliente").size()
k = {
 "K1 Ventas netas (S/)": X.importe_neto.sum(),
 "K2 Nº de pedidos": ped.shape[0],
 "K3 Ticket promedio por pedido (S/)": ped.neto.mean(),
 "K4 Margen bruto (S/)": X.margen_bruto.sum(),
 "K5 Margen bruto (%)": X.margen_bruto.sum()/X.importe_neto.sum()*100,
 "K6 Clientes identificados": ident.shape[0],
 "K7 Tasa de clientes recurrentes (%)": (ident >= 2).mean()*100,
 "K8 Participación ventas apps delivery (%)": X[X.origen == "CSV externo"].importe_neto.sum()/X.importe_neto.sum()*100,
 "K9 Comisión pagada a plataformas (S/)": X.comision_plataforma.sum(),
 "K10 Calificación promedio apps (1-5)": X.calificacion.mean(),
 "K11 Tiempo de entrega promedio apps (min)": X.tiempo_entrega_min.mean()}
kp = pd.DataFrame({"kpi": k.keys(), "valor": [round(v, 2) for v in k.values()]}); kp.to_csv(f"{RES}/kpis.csv", index=False, encoding="utf-8-sig"); print(kp.to_string(index=False))

# ------------------------------------------------------------------ OLAP
# ROLL-UP: día -> mes -> trimestre -> año
mes = X.groupby(["anio", "trimestre", "anio_mes"]).agg(ventas=("importe_neto", "sum"), margen=("margen_bruto", "sum")).reset_index()
trim = X.groupby(["anio", "trimestre"]).agg(ventas=("importe_neto", "sum"), margen=("margen_bruto", "sum")).reset_index()
anio = X.groupby("anio").agg(ventas=("importe_neto", "sum"), margen=("margen_bruto", "sum")).reset_index()
mes.to_csv(f"{RES}/olap_rollup_mes.csv", index=False); trim.to_csv(f"{RES}/olap_rollup_trimestre.csv", index=False); anio.to_csv(f"{RES}/olap_rollup_anio.csv", index=False)
# DRILL-DOWN: categoría -> plato (Ceviches)
cat = X.groupby("categoria").agg(ventas=("importe_neto", "sum"), unidades=("cantidad", "sum")).sort_values("ventas", ascending=False).reset_index()
dd = X[X.categoria == "Ceviches"].groupby("nombre_plato").agg(ventas=("importe_neto", "sum"), unidades=("cantidad", "sum"), margen=("margen_bruto", "sum")).sort_values("ventas", ascending=False).reset_index()
cat.to_csv(f"{RES}/olap_drilldown_categoria.csv", index=False); dd.to_csv(f"{RES}/olap_drilldown_ceviches_plato.csv", index=False)
# SLICE: canal = PedidosYa
sl = X[X.canal == "PedidosYa"].groupby("anio_mes").agg(ventas_brutas=("importe_bruto", "sum"), comision=("comision_plataforma", "sum"), neto=("importe_neto", "sum")).reset_index()
sl.to_csv(f"{RES}/olap_slice_pedidosya.csv", index=False)
# DICE: T1-2026 x (Ceviches, Arroces) x (Yape, Plin)
dc = X[(X.anio == 2026) & (X.trimestre == 1) & (X.categoria.isin(["Ceviches", "Arroces"])) & (X.metodo_pago.isin(["Yape", "Plin"]))]
dice = dc.pivot_table(index="categoria", columns="metodo_pago", values="importe_neto", aggfunc="sum", margins=True, margins_name="Total").round(2)
dice.to_csv(f"{RES}/olap_dice_t1_2026.csv")
# PIVOT: día de semana x turno (solo SQL Server tiene turno)
pv = X[X.origen == "SQL Server"].pivot_table(index="dia_semana", columns="turno", values="importe_neto", aggfunc="sum")
orden = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]; pv = pv.loc[orden][["Almuerzo (11-15h)", "Tarde (15-18h)", "Noche (18-22h)"]]; pv.round(2).to_csv(f"{RES}/olap_pivot_dia_turno.csv")
# CUBO (categoría x canal x trimestre)
cubo = X.groupby(["anio", "trimestre", "categoria", "canal"]).agg(ventas=("importe_neto", "sum")).reset_index(); cubo.to_csv(f"{RES}/olap_cubo_categoria_canal_trimestre.csv", index=False)
print("\nRoll-up trimestre:\n", trim.round(0).to_string(index=False)); print("\nDrill-down categoría:\n", cat.round(0).to_string(index=False))

# ------------------------------------------------------------------ Gráficos: dashboard de referencia (réplica de las vistas de Power BI)
fig = plt.figure(figsize=(15, 9.2)); fig.patch.set_facecolor("#F4F6F9")
fig.suptitle("Cevichería “La Esquina” · Tablero de ventas 2025-10 a 2026-09 (fuente: Data Warehouse)", x=0.02, ha="left", fontsize=15, fontweight="bold", color=azul)
cards = [("Ventas netas", f"S/ {k['K1 Ventas netas (S/)']/1e6:,.2f} M", azul), ("Ticket promedio", f"S/ {k['K3 Ticket promedio por pedido (S/)']:,.0f}", verde),
         ("Margen bruto", f"{k['K5 Margen bruto (%)']:.1f} %", naranja), ("Clientes recurrentes", f"{k['K7 Tasa de clientes recurrentes (%)']:.1f} %", rojo),
         ("Ventas vía apps", f"{k['K8 Participación ventas apps delivery (%)']:.1f} %", gris)]
for i, (t, v, c) in enumerate(cards):
    ax = fig.add_axes([0.02+i*0.196, 0.84, 0.18, 0.09]); ax.set_facecolor("white"); ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values(): s.set_visible(False)
    ax.add_patch(plt.Rectangle((0, 0), 0.03, 1, color=c, transform=ax.transAxes)); ax.text(0.08, 0.66, t, fontsize=10, color="#555", transform=ax.transAxes); ax.text(0.08, 0.16, v, fontsize=18, fontweight="bold", color=c, transform=ax.transAxes)
ax = fig.add_axes([0.07, 0.47, 0.42, 0.30]); m = mes.copy(); ax.plot(m.anio_mes, m.ventas, marker="o", color=azul, lw=2); ax.fill_between(range(len(m)), m.ventas, alpha=.12, color=azul)
ax.set_title("Ventas netas por mes (roll-up día→mes)"); ax.yaxis.set_major_formatter(soles); ax.tick_params(axis="x", rotation=45, labelsize=8); ax.grid(axis="y", alpha=.3)
ax = fig.add_axes([0.58, 0.47, 0.38, 0.30]); t = X.groupby("nombre_plato").importe_neto.sum().nlargest(8).sort_values(); ax.barh(t.index, t.values, color=verde); ax.xaxis.set_major_formatter(soles); ax.set_title("Top 8 platos por ventas netas"); ax.tick_params(labelsize=8)
ax = fig.add_axes([0.05, 0.06, 0.26, 0.32]); cn = X.groupby("canal").importe_neto.sum(); ax.pie(cn.values, labels=cn.index, autopct="%1.0f%%", colors=[azul, verde, naranja, rojo, gris], textprops={"fontsize": 8}, wedgeprops={"width": .45}); ax.set_title("Ventas netas por canal")
ax = fig.add_axes([0.40, 0.06, 0.26, 0.32]); im = ax.imshow(pv.values, cmap="YlGnBu", aspect="auto"); ax.set_xticks(range(3)); ax.set_xticklabels([c.split(" ")[0] for c in pv.columns], fontsize=8); ax.set_yticks(range(7)); ax.set_yticklabels(pv.index, fontsize=8); ax.set_title("Mapa de calor: día × turno (S/)")
for i in range(7):
    for j in range(3): ax.text(j, i, f"{pv.values[i, j]/1000:,.0f}k", ha="center", va="center", fontsize=7, color="white" if pv.values[i, j] > pv.values.max()*.55 else "#222")
ax = fig.add_axes([0.75, 0.06, 0.21, 0.32]); c2 = cat.sort_values("ventas"); ax.barh(c2.categoria, c2.ventas, color=naranja); ax.xaxis.set_major_formatter(soles); ax.set_title("Ventas por categoría (drill-down)"); ax.tick_params(labelsize=8)
fig.savefig(f"{GRA}/dashboard_referencia.png", dpi=130); plt.close(fig)

fig, axs = plt.subplots(1, 3, figsize=(15, 4.4)); fig.patch.set_facecolor("white")
tq = trim.assign(t=lambda d: d.anio.astype(str)+"-T"+d.trimestre.astype(str)); axs[0].bar(tq.t, tq.ventas, color=azul); axs[0].yaxis.set_major_formatter(soles); axs[0].set_title("Roll-up: ventas por trimestre"); axs[0].tick_params(axis="x", rotation=30)
axs[1].barh(dd.nombre_plato[::-1], dd.ventas[::-1], color=verde); axs[1].xaxis.set_major_formatter(soles); axs[1].set_title("Drill-down: platos de la categoría Ceviches"); axs[1].tick_params(labelsize=8)
w = 0.4; x = np.arange(len(sl)); axs[2].bar(x-w/2, sl.ventas_brutas, w, label="Venta bruta", color=azul); axs[2].bar(x+w/2, sl.comision, w, label="Comisión", color=rojo); axs[2].set_xticks(x); axs[2].set_xticklabels(sl.anio_mes, rotation=45, fontsize=8); axs[2].yaxis.set_major_formatter(soles); axs[2].legend(fontsize=8); axs[2].set_title("Slice: solo canal PedidosYa")
plt.tight_layout(); fig.savefig(f"{GRA}/olap_operaciones.png", dpi=130); plt.close(fig)
print("OK graficos")
