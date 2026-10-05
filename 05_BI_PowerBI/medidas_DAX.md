# Tablero de Power BI – Cevichería “La Esquina”

Este archivo explica cómo armamos el tablero a partir del Data Warehouse: de dónde salen los datos, cómo se relacionan las tablas, qué medidas creamos y qué muestra cada hoja.

## 1. De dónde salen los datos

- **SQL Server (modo Importar)

## 2. Relaciones y fechas
- Cada dimensión se relaciona con `Fact_Ventas` por su llave `sk_*` (por ejemplo `Dim_Plato[sk_plato]` con `Fact_Ventas[sk_plato]`). Son relaciones de uno a varios y el filtro va en un solo sentido, de la dimensión hacia el hecho. No hay relaciones entre dimensiones.
- `Dim_Fecha` está marcada como tabla de fechas (columna `fecha`).
- Ordenamos `mes_nombre` por `mes_num` y `dia_semana` por `dia_semana_num`, para que los meses y los días no salgan en orden alfabético.
- Creamos una columna en `Dim_Fecha` para los gráficos por trimestre:
  ```DAX
  anio_trimestre = Dim_Fecha[anio] & "-T" & Dim_Fecha[trimestre]
  ```
- Jerarquías: fecha (`anio` → `trimestre` → `anio_mes` → `fecha`) y plato (`categoria` → `nombre_plato`). Son las que hacen posibles el roll-up y el drill-down.

## 3. Medidas

```DAX
Ventas Netas      = SUM ( Fact_Ventas[importe_neto] )
Ventas Brutas     = SUM ( Fact_Ventas[importe_bruto] )
Pedidos           = DISTINCTCOUNT ( Fact_Ventas[nro_pedido] )
Ticket Promedio   = DIVIDE ( [Ventas Netas], [Pedidos] )
Margen Bruto      = SUM ( Fact_Ventas[margen_bruto] )
Margen Bruto %    = DIVIDE ( [Margen Bruto], [Ventas Netas] )
Comision Apps     = SUM ( Fact_Ventas[comision_plataforma] )
Calificacion Apps = AVERAGE ( Fact_Ventas[calificacion] )
Tiempo Entrega    = AVERAGE ( Fact_Ventas[tiempo_entrega_min] )

% Ventas Apps     = DIVIDE ( CALCULATE ( [Ventas Netas], Fact_Ventas[origen] = "CSV externo" ), [Ventas Netas] )

Clientes Recurrentes % =
VAR Tabla =
    SUMMARIZE (
        FILTER ( Fact_Ventas, RELATED ( Dim_Cliente[es_cliente_identificado] ) = 1 ),
        Dim_Cliente[sk_cliente],
        "@ped", DISTINCTCOUNT ( Fact_Ventas[nro_pedido] )
    )
RETURN DIVIDE ( COUNTROWS ( FILTER ( Tabla, [@ped] >= 2 ) ), COUNTROWS ( Tabla ) )

Ventas Netas AA   = CALCULATE ( [Ventas Netas], SAMEPERIODLASTYEAR ( Dim_Fecha[fecha] ) )
Crecimiento %     = DIVIDE ( [Ventas Netas] - [Ventas Netas AA], [Ventas Netas AA] )
Participacion Cat = DIVIDE ( [Ventas Netas], CALCULATE ( [Ventas Netas], ALL ( Dim_Plato[categoria] ) ) )

-- Para la hoja “Delivery apps”
Pedidos Apps      = CALCULATE ( [Pedidos], Fact_Ventas[origen] = "CSV externo" )
Comision %        = DIVIDE ( [Comision Apps], CALCULATE ( [Ventas Brutas], Fact_Ventas[origen] = "CSV externo" ) )
Margen por Pedido = DIVIDE ( [Margen Bruto], [Pedidos] )
```

| Medida | Qué calcula, en simple |
|---|---|
| Ventas Netas | Lo que realmente le queda a la cevichería: la venta menos la comisión que cobran las apps. |
| Ventas Brutas | La venta antes de descontar comisiones. |
| Pedidos | Cuántos pedidos distintos hay en el contexto que estás mirando. |
| Ticket Promedio | Cuánto deja en promedio cada pedido (ventas netas ÷ pedidos). |
| Margen Bruto % | Qué parte de la venta neta queda después del costo estimado de los platos. |
| Clientes Recurrentes % | De los clientes identificados, cuántos volvieron a comprar (dos pedidos o más). No cuenta al “cliente de paso” ni al “cliente app”. |
| % Ventas Apps | Qué tanto de la venta neta entra por PedidosYa y Rappi. |
| Comision % | Qué porcentaje de la venta bruta de las apps se va en comisión. |
| Margen por Pedido | Cuánto margen deja cada pedido en promedio; sirve para comparar canales. |

## 4. Las tres hojas del tablero

**Hoja 1 – Resumen.** Cinco tarjetas (Ventas Netas, Ticket Promedio, Margen Bruto %, Clientes Recurrentes % y % Ventas Apps), la línea de ventas netas por mes, el top 8 de platos, el anillo de ventas por canal, el mapa de calor día × turno (matriz con formato condicional) y las ventas por categoría.

**Hoja 2 – OLAP.** Aquí se demuestran las operaciones:
- *Roll-up y drill-down:* una matriz con `categoria` y debajo `nombre_plato`, con `Ventas Netas` y `Margen Bruto %`; las flechas del visual suben y bajan de nivel. Al lado, gráficos de columnas y de línea con `anio_trimestre` y `anio_mes`.
- *Slice y dice:* segmentadores de año, trimestre, categoría, método de pago y canal. Los de categoría y método de pago permiten marcar más de una opción (selección múltiple).

**Hoja 3 – Delivery apps.** Responde la pregunta de cuánto cuesta vender por las aplicaciones y si conviene:
- *Ventas Brutas vs Comisión Apps* por plataforma (gráfico de columnas agrupadas). Para que solo aparezcan PedidosYa y Rappi, filtramos el visual con `Dim_Canal.
- Tarjetas de `Pedidos Apps`, `Calificacion Apps` y `Tiempo Entrega`. Estas tres, filtradas a las apps, porque los pedidos del salón no tienen calificación ni tiempo de entrega.
- *Margen Bruto % por canal* (todos los canales): permite ver que las apps dejan menos margen que el salón o el delivery propio.
- *Ticket promedio por canal* (`Ticket Promedio` o `Margen por Pedido`, todos los canales): un pedido de app trae un solo plato, por eso su ticket es mucho más bajo.

## 5. OLAP
**roll-up** (subir de nivel, por ejemplo de plato a categoría), **drill-down** (bajar, de Ceviches a sus platos), **slice** (un solo filtro, por ejemplo el canal PedidosYa) y **dice** (varios filtros a la vez). El mapa de calor día × turno es un **pivot**. Las mismas operaciones están en `13_OLAP_Consultas.sql` (T-SQL) y en `olap_kpis.py` (pandas), por si se quieren comprobar fuera de Power BI.

## 6. Gobernanza de los KPIs
| KPI | Fuente | Fórmula | Responsable de actualizar | Criterio de calidad |
|---|---|---|---|---|
| Ventas Netas | Fact_Ventas (SQL Server + CSV externo) | Σ importe_neto | Analista de datos (rol AnalistaDatos) | Concilia con Σ Pedido.monto_total: 0 discrepancias (paso T08 del ETL) |
| Ticket Promedio | Fact_Ventas | Ventas Netas ÷ pedidos distintos | Analista de datos | nro_pedido único; pedidos > 0 |
| Margen Bruto % | Fact_Ventas + Dim_Plato | Σ (importe_neto − costo_total) ÷ Σ importe_neto | Administrador | costo_estimado ≥ 0; es una estimación (supuesto S5) |
| Clientes Recurrentes % | Fact_Ventas + Dim_Cliente | Clientes identificados con ≥ 2 pedidos ÷ clientes identificados | Administrador | Excluye “cliente de paso” y “cliente app” |
| % Ventas Apps | Fact_Ventas | Ventas netas de origen CSV externo ÷ ventas netas | Administrador | Sin duplicados por order_ref (paso T01) |
| Comision % | Fact_Ventas | Σ comisión ÷ Σ venta bruta de apps | Analista de datos | Comisión entre 18 % y 25 % por pedido |
| Calificación Apps | CSV externo | Promedio de calificación (se ignoran vacíos) | Analista de datos | Escala 1–5; 739 de 5 400 pedidos sin calificar |
| Tiempo Entrega | CSV externo | Promedio de minutos | Analista de datos | Entre 12 y 80 minutos |

## 7. Valores de control

| Indicador | Valor |
|---|---|
| Ventas Netas | S/ 1 695 893.98 |
| Pedidos | 17 382 |
| Ticket Promedio | S/ 97.57 |
| Margen Bruto % | 64.76 % |
| Clientes Recurrentes % | 62.26 % |
| % Ventas Apps | 12.16 % |
| Ceviches (categoría) | S/ 679 792.37; el plato líder es el Tiradito Nikkei con S/ 135 945.34 |
| Dice (2026, T1, Arroces y Ceviches, Plin y Yape) | S/ 86 153.00 |

Hoja “Delivery apps” (solo apps):

| Indicador | PedidosYa | Rappi | Total apps |
|---|---|---|---|
| Pedidos | 3 203 | 2 197 | 5 400 |
| Ventas Brutas | S/ 157 109.70 | S/ 106 251.20 | S/ 263 360.90 |
| Comisión | S/ 36 938.21 | S/ 20 191.71 | S/ 57 129.92 |
| Comisión % | 23.51 % | 19.00 % | 21.69 % |
| Margen Bruto % | 59.07 % | 61.33 % | 60.01 % |
| Calificación | 3.96 | 3.97 | 3.97 |
| Tiempo de entrega (min) | 34.05 | 34.31 | 34.15 |

