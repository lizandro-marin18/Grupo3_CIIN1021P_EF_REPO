# Proyecto integrador CIIN1021P – Cevichería “La Esquina” (Grupo 3)
Sistema integrado de base de datos segura, automatizada e inteligente: **SQL Server → CSV → ETL (pandas) → Data Warehouse (Kimball) → OLAP → Power BI**, con **MongoDB** (semiestructurado) y **Apache Spark** (Big Data).
Nombre del repositorio: `Grupo3_CIIN1021P_EF_REPO` · Informe: `Grupo3_CIIN1021P_EF.pdf`.

## Estructura (una carpeta por bloque temático)
| Carpeta | Contenido |
|---|---|
| `00_Datos/` | `generar_datos.py` (semilla fija) → `Crudos/` (CSV sucios, >5 000 filas), `Externos/` (CSV delivery, JSON reseñas, feriados), `simular_carga_sql.py` → `Export_SQL/` (equivale al export de SQL Server) |
| `01_Automatizacion/` | T-SQL: `01_BaseDatos` (E-R), `02_Funciones` (3), `03_Procedimientos` (4 SP con TRY/CATCH, COMMIT/ROLLBACK/SAVEPOINT), `04_Triggers` (5), `05_Pruebas_Validacion`, `09_Carga_Datos`, `10_Export_CSV_para_DW` |
| `02_Seguridad/` | `06_Roles_Privilegios_RLS` (6 roles, DDM, RLS), `07_Indices_Rendimiento` (plan antes/después), `08_Backup_Restore` (FULL+DIFF+LOG, restore probado) |
| `03_NoSQL_MongoDB/` | `mongodb_resenas.js` (CRUD + agregaciones sobre 5 200 reseñas) |
| `04_DataWarehouse_ETL/` | `etl_cevicheria.py`, `12_DW_DDL.sql`, `DW_csv/` `logs/etl_log.txt` |
| `05_BI_PowerBI/` | `medidas_DAX.md` (modelo, DAX, gobernanza), `13_OLAP_Consultas.sql`, `olap_kpis.py`, `olap_resultados/`, `graficos/` |
| `06_BigData_Spark/` | `Cevicheria_Spark.ipynb` (ejecutado), `benchmark_tiempos.csv`, `11_Benchmark_SQLServer.sql`, `graficos/` |
| `07_Documentacion/` | informe final|

## Herramientas
SQL Server Developer/Express + SSMS · Python 3.12 (pandas, numpy, matplotlib, seaborn, pyspark 4.2, nbformat) · Apache Spark 4.2 + JDK 21 · MongoDB Community + mongosh · Power BI Desktop (gratuito) · Graphviz.

## Orden de ejecución
1. `python 00_Datos/generar_datos.py` (opcional: los CSV ya están incluidos).
2. SQL Server: `01_BaseDatos` → `02_Funciones` → `03_Procedimientos` → `04_Triggers` → `09_Carga_Datos` (ajustar rutas) → `05_Pruebas_Validacion` → `06_Roles…` → `07_Indices…` → `08_Backup…` (ajustar rutas `C:\Backups`).
3. Exportar CSV (`10_Export_CSV_para_DW.sql`). *Sin SQL Server:* `python 00_Datos/simular_carga_sql.py` reproduce el export con las mismas reglas.
4. `python 04_DataWarehouse_ETL/etl_cevicheria.py` → `DW_csv/`, `logs/etl_log.txt`. Opcional: `12_DW_DDL.sql` para cargar el DW en SQL Server.
5. `python 05_BI_PowerBI/olap_kpis.py` → KPIs y OLAP; en Power BI seguir `medidas_DAX.md`.
6. `06_BigData_Spark/Cevicheria_Spark.ipynb` (Colab o local; configura JDK 21 + Spark 4.2).
7. MongoDB: `mongoimport --db Cevicheria_NoSQL --collection Resenas --file 00_Datos/Externos/Resenas_Clientes.jsonl` y luego `mongosh < 03_NoSQL_MongoDB/mongodb_resenas.js`.

## Supuestos y reglas de calidad
S1 cliente nulo → 9999 · S2 fecha inválida → fecha de carga (`fecha_imputada=1`) · S3 salario nulo permitido · R1 duplicados se descartan · R4 monto ≤ 0 se rechaza · R5 DNI ≠ 8 dígitos → NULL · R6 detalle huérfano se rechaza.
Datos personales: el DW no contiene DNI en claro, email, teléfono ni salario (SHA-256 + sal, Ley N.° 29733).

## Nota de transparencia
Los datos son **simulados** (generador reproducible). Los scripts T-SQL deben ejecutarse en su instancia; los resultados de Python/Spark incluidos fueron ejecutados y sus logs se conservan.
