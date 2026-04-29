-- Nivel 1
-- Ejercicio 1: Arquitectura de Datos (Lógica vs. Física)

-- creación proyecto
gcloud projects create sprint3-analytics-francesca --name="Sprint 3 Analytics Francesca"

-- verifico que el proyecto existe
gcloud projects list

-- activo el proyecto en la sesion
gcloud config set project sprint3-analytics-francesca

-- Dataset sprint3_bronze (capa Bronze): creado con la UI de BigQuery.
-- Ubicación: EU (multi-región europea).
-- Ver PDF de entrega (capturas de pantalla).
-- Nota: la descripción no se añadió debido a una limitación del modo Sandbox al editar el dataset por la UI.

-- creación dataset sprint3_silver con código sql

CREATE SCHEMA IF NOT EXISTS sprint3_silver
OPTIONS (
  location = 'EU',
  description = 'Capa Silver: datos limpios, tipados y deduplicados.'
);

-- creación sprint3_gold con Cloud Shell (Línea de comandos bq)

bq --location=EU mk \
  --dataset \
  --description="Capa Gold: datos agregados listos para informes y dashboards." \
  sprint3-analytics-francesca:sprint3_gold

-- Ejercicio 2: Ingesta en Capa Bronze (Conexión DDL)

-- Verifico la presencia de cabecera ejecutando en Cloud Shell (en este y en los casos siguientes):
-- gcloud storage cat gs://bootcamp-data-analytics-public/ERP/transactions.csv | head -3
-- La primera fila contiene los nombres de columnas, por lo que aplico skip_leading_rows = 1.
-- transactions con ; como separador

CREATE EXTERNAL TABLE IF NOT EXISTS sprint3_bronze.transactions_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/ERP/transactions.csv'],
  field_delimiter = ';',
  skip_leading_rows = 1
); 

-- companies
-- Todas las columnas se definen como STRING para preservar los datos crudos sin transformación, siguiendo la filosofía de la capa Bronze.
CREATE EXTERNAL TABLE IF NOT EXISTS sprint3_bronze.companies_raw (
  company_id    STRING,
  company_name  STRING,
  phone         STRING,
  email         STRING,
  country       STRING,
  website       STRING
)
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/ERP/companies.csv'],
  skip_leading_rows = 1
);

-- american_users_raw
CREATE EXTERNAL TABLE IF NOT EXISTS sprint3_bronze.american_users_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/american_users.csv'],
  skip_leading_rows = 1
);

-- european_users_raw
CREATE EXTERNAL TABLE IF NOT EXISTS sprint3_bronze.european_users_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/european_users.csv'],
  skip_leading_rows = 1
);

-- credit_cards_raw
CREATE EXTERNAL TABLE IF NOT EXISTS sprint3_bronze.credit_cards_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/credit_cards.csv'],
  skip_leading_rows = 1
);

-- EJERCICIO 3: Carga de Datos Locales (Upload)
-- El archivo products.csv (sprint 2) no se encuentra en el Data Lake, por lo que se sube manualmente desde la UI de BigQuery mediante la opción "Subir" (Upload). 
-- Esto genera una tabla NATIVA, a diferencia de las tablas externas del Ejercicio 2. Capturas den el PDF.

-- Ejercicio 4: Arquitectura y Rendimiento. Materialización de Datos
-- a) Materialización de Datos (Asistido por IA)
-- Capturas en el pdf. He ejecutado este codigo:
CREATE OR REPLACE TABLE `sprint3-analytics-francesca.sprint3_bronze.transactions_raw_native`
AS
SELECT * FROM `sprint3-analytics-francesca.sprint3_bronze.transactions_raw`

-- b) Auditoría de Costes: ver pdf.

-- consulta sobte la Tabla externa, transactions_raw
SELECT id 
FROM sprint3_bronze.transactions_raw;

-- consulta sobre la Tabla nativa, transactions_raw_native
SELECT id
FROM sprint3_bronze.transactions_raw_native;

-- c)  El peligro del LIMIT
SELECT *
FROM sprint3_bronze.transactions_raw
LIMIT 10;

-- Ejercicio 5: Adaptación de Sintaxis (Reporting)
-- Tu jefe quiere saber cuáles fueron los 5 días con mayores ingresos del año 2021 . Reto: Probablemente el campo timestamp es un STRING. 
-- Tendrás que investigar funciones de BigQuery ( SUBSTR, CAST, PARSE_TIMESTAMP) para filtrar el año y agrupar por fecha correctamente.
SELECT DATE(timestamp) AS dia, ROUND(SUM(amount),2) AS cantidad_ingresos_por_dia     
FROM sprint3_bronze.transactions_raw_native
WHERE EXTRACT(YEAR FROM timestamp) = 2021
AND declined = 0                                                    
GROUP BY DATE(timestamp)
ORDER BY cantidad_ingresos_por_dia DESC
LIMIT 5;

-- Si la columna timestamp fuera STRING, habría tenido que hacer algo como: 
SELECT 
  DATE(PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', timestamp)) AS dia, 
  ROUND(SUM(amount), 2) AS cantidad_ingresos_por_dia     
FROM sprint3_bronze.transactions_raw_native
WHERE EXTRACT(YEAR FROM PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', timestamp)) = 2021
  AND declined = 0                                                    
GROUP BY DATE(PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', timestamp))
ORDER BY cantidad_ingresos_por_dia DESC
LIMIT 5;

-- APUNTES
-- PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', timestamp) Convierte un STRING en TIMESTAMP
-- '%Y-%m-%d %H:%M:%S'. Es un patrón que le dice a BigQuery: "el texto viene como año-mes-día hora:minuto:segundo".

-- EXTRACT(YEAR FROM ...) Saca el año de ese TIMESTAMP.

-- GROUP BY DATE(PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', timestamp)) >>> esta línea: tiene que ser idéntica a lo que puse en el SELECT (línea 2, sin el AS dia).

-- Ejercicio 6: Consultas Complejas
SELECT c.company_name AS nombre_empresa, c.country AS pais, DATE(t.timestamp) AS fecha, ROUND(t.amount, 2) AS valor_transaccion
FROM sprint3_bronze.companies_raw c
JOIN sprint3_bronze.transactions_raw t
ON c.company_id = t.business_id
WHERE t.amount BETWEEN 100 AND 200
AND DATE(t.timestamp) IN ('2015-04-29', '2018-07-20', '2024-03-13')
ORDER BY valor_transaccion DESC;

-- Nivel 2: Limpieza y Transformación (ELT)

-- Ejercicio 1: Limpieza de Productos (Data Quality)

-- mejor versión con replace. Utilizo REPLACE en lugar de SUBSTR porque REPLACE actúa solo si encuentra el patrón exacto, lo que hace que la query sea más robusta.
-- Uso SAFE_CAST en lugar de CAST para que la query no rompa ante valores corruptos (devuelve NULL en su lugar).
CREATE OR REPLACE TABLE sprint3_silver.products_clean AS
SELECT 
  id AS product_id,
  product_name AS name,
  SAFE_CAST(price AS FLOAT64) AS price,
  colour,
  weight,
  SAFE_CAST(REPLACE(warehouse_id, 'WH-', '') AS INT64) AS warehouse_id
FROM sprint3_bronze.products_raw;

-- Aquí versión con SUBSTR en lugar de REPLACE que hice en un primer momento. No tenerla en cuenta
-- SUBSTR es destructivo cuando los datos no encajan exactamente con el patrón esperado.
CREATE OR REPLACE TABLE sprint3_silver.products_clean AS
SELECT 
  id AS product_id,
  product_name AS name,
  SAFE_CAST(SUBSTR(price, 2) AS FLOAT64) AS price,
  colour AS colour,
  weight AS weight,
  SAFE_CAST(SUBSTR(warehouse_id, 4) AS INT64) AS warehouse_id
FROM sprint3_bronze.products_raw;


-- Ejercicio 2: Creación de Transacciones Limpias (Capa Silver)

-- Nota: el enunciado asume que timestamp es STRING, pero la autodetección de la tabla en Bronze ya la tipó como TIMESTAMP. Por tanto, PARSE_TIMESTAMP no es necesario; se mantiene un SAFE_CAST como garantía.

-- Nota 2: Aunque el enunciado no lo pida claramente, ya que estamos en la capa Silver, que es donde se hace “limpieza”, convierto product_ids a array.
-- ARRAY: empieza a construir un ARRAY nuevo
-- SELECT SAFE_CAST(TRIM(x) AS INT64):
------ x = cada valor del array tras el split
------ TRIM(x): elimina espacios
------ SAFE_CAST(... AS INT64): convierte a número y si falla devuelve NULL en vez de error
-- FROM UNNEST(SPLIT(product_ids, ',')) AS x
----- SPLIT(product_ids, ',') convierte el string en array: es decir desde "17, 66, 3" a ['17', ' 66', ' 3']
----- UNNEST(...): Convierte ese array en filas
----- AS x: Le da nombre a cada elemento 
----- WHERE TRIM(x) != '': filtra los elementos vacíos


CREATE OR REPLACE TABLE sprint3_silver.transactions_clean AS
SELECT 
  id AS transaction_id,
  card_id, 
  business_id,
  SAFE_CAST(timestamp AS TIMESTAMP) AS timestamp,
  IFNULL(SAFE_CAST(amount AS FLOAT64), 0) AS amount,
  declined,
  ARRAY(
    SELECT SAFE_CAST(TRIM(x) AS INT64)
    FROM UNNEST(SPLIT(product_ids, ',')) AS x
    WHERE TRIM(x) != ''
  ) AS product_ids,
  user_id,
  SAFE_CAST(lat AS FLOAT64) AS lat,
  SAFE_CAST(longitude AS FLOAT64) AS longitude
FROM sprint3_bronze.transactions_raw;

-- Esta sería la versión correcta sin la autodetección de la tabla en Bronze:

CREATE OR REPLACE TABLE sprint3_silver.transactions_clean AS
SELECT 
  id AS transaction_id,
  card_id, 
  business_id,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', timestamp) AS timestamp,
  IFNULL(SAFE_CAST(amount AS FLOAT64), 0) AS amount,
  declined,
  ARRAY(
    SELECT SAFE_CAST(TRIM(x) AS INT64)
    FROM UNNEST(SPLIT(product_ids, ',')) AS x
    WHERE TRIM(x) != ''
  ) AS product_ids,
  user_id,
  SAFE_CAST(lat AS FLOAT64) AS lat,
  SAFE_CAST(longitude AS FLOAT64) AS longitude
FROM sprint3_bronze.transactions_raw;

-- Ejercicio 3: Unificación de Usuarios (UNION)

CREATE OR REPLACE TABLE sprint3_silver.users_combined AS
SELECT 
  id AS user_id,          -- renombrado de id genérico a user_id específico
  name,
  surname, 
  phone,
  email,
  birth_date,
  country,
  city,
  postal_code,
  address, 
  'Europe' AS origin      -- columna para identificar el origen
FROM sprint3_bronze.european_users_raw

UNION ALL

SELECT 
  id AS user_id, -- renombrado de id genérico a user_id específico
  name,
  surname, 
  phone,
  email,
  birth_date,
  country,
  city,
  postal_code,
  address, 
  'America' AS origin    -- columna para identificar el origen
FROM sprint3_bronze.american_users_raw;

-- Ejercicio 4: Materialización de Compañías y Tarjetas de Crédito
-- Tabla companies
-- Nota: aquí la columna id ya estaba nombrada como company_id desde Bronze, por lo que no requiere renombrado.
CREATE OR REPLACE TABLE sprint3_silver.companies_clean AS   -- sin EXTERNAL. Le dice a BigQuery: "crea una tabla nativa, copia los datos físicamente dentro de tu almacenamiento".
SELECT 
  company_id,        
  company_name,
  phone,
  email,
  country,
  website
FROM sprint3_bronze.companies_raw;

-- Tabla credit_cards
-- Renombro id como credit_card_id por coherencia con el resto de tablas, tal y como pide el enunciado
CREATE OR REPLACE TABLE sprint3_silver.credit_cards_clean AS
SELECT 
  id AS credit_card_id,        
  user_id,
  iban,
  pan,
  pin,
  cvv,
  track1,
  track2,
  expiring_date
FROM sprint3_bronze.credit_cards_raw;

-- Nivel 3: Presentación de Datos y Creación de Vistas
-- Ejercicio 1: La Vista de Marketing (Lógica de Negocio)

-- Creo la vista llamada sprint3_gold.v_marketing_kpis

-- Clasifico el cliente con CASE WHEN: si la media de compra supera 260 €, lo etiqueta como 'Premium'; en caso contrario, 'Standard'.
-- Repite la fórmula ROUND(AVG(...), 2) en lugar de usar el alias porque SQL no permite referenciar alias dentro del mismo SELECT.
CREATE OR REPLACE VIEW sprint3_gold.v_marketing_kpis AS
SELECT 
  c.company_name AS nombre_empresa,
  c.phone AS telefono, 
  c.country AS pais, 
  ROUND(AVG(t.amount),2) AS media_de_compra,
CASE
  WHEN ROUND(AVG(t.amount),2) > 260 THEN 'Premium'
  ELSE 'Standard'
END AS client_tier
FROM sprint3_silver.companies_clean c
JOIN sprint3_silver.transactions_clean t
ON c.company_id = t.business_id
WHERE t.declined = 0
GROUP BY c.company_id, c.company_name, c.phone, c.country;

-- Ahora realizo una consulta SELECT * sobre la vista
SELECT *
FROM sprint3_gold.v_marketing_kpis
ORDER BY 
  client_tier,             -- Premium antes que Standard alfabéticamente
  media_de_compra DESC;    -- Dentro de cada grupo, media_de_compra DESC es decir los mayores primero

-- Otra posibilidad de hacer la consulta SELECT * sobre la vista sería la siguiente que es más robusta si en futuro se añade una nueva etiqueta. Aún así, la anterior en este caso debería ser suficiente
SELECT *                                                    -- Selecciono todas las columnas 
FROM sprint3_gold.v_marketing_kpis                          -- FROM la vista que acabo de crear
ORDER BY                                                    -- todo lo que viene después son los criterios de ordenación
  CASE WHEN client_tier = 'Premium' THEN 0 ELSE 1 END,      -- esto dice: "Para cada fila, mira el valor de client_tier. Si es 'Premium', devuelve 0. Si no, devuelve 1" = cada fila se "etiqueta" temporalmente con 0 o 1. BQuery por defecto ordena asc
  media_de_compra DESC;                                     -- esto dice: dentro de cada grupo del primer criterio, ordena por media_de_compra

-- Ejercicio 2: Ranking de Productos (La Potencia de los Arrays)

CREATE OR REPLACE TABLE sprint3_gold.product_sales_ranking AS   -- Crea la tabla en Gold
WITH ventas_por_producto AS (                                   -- Empieza la CTE (tabla temporal con nombre). Va a contar ventas por producto.
  SELECT 
    p AS product_id,                                            -- el producto (renombrado)
    COUNT(*) AS total_sold                                      -- cuántas veces aparece        
  FROM sprint3_silver.transactions_clean t                      -- lee de la tabla de transacciones, con alias t
  CROSS JOIN UNNEST(t.product_ids) AS p                         -- Explota el array product_ids en filas individuales. Cada elemento se llama p.
  GROUP BY p                                                    -- Agrupa por producto, para que COUNT(*) cuente por separado cada uno.
)                                                               -- Cierra la CTE
SELECT                                                          -- Las 4 columnas del producto y el conteo de ventas. 
  p.product_id,
  p.name,
  p.price,
  p.colour,
  IFNULL(v.total_sold, 0) AS total_sold                         -- Si un producto no tuvo ventas, pone 0 en lugar de NULL.
FROM sprint3_silver.products_clean p                            -- Lee la tabla de productos (alias p).
LEFT JOIN ventas_por_producto v                                 -- Une productos con sus ventas. LEFT para que aparezcan todos los productos, incluso los sin ventas.
  ON p.product_id = v.product_id;

--

Versión Ejercicio 2: Ranking de Productos con alias más claros

WITH ventas_por_producto AS (
  SELECT 
    pid AS product_id,                          -- pid (product id)
    COUNT(*) AS total_sold
  FROM sprint3_silver.transactions_clean t
  CROSS JOIN UNNEST(t.product_ids) AS pid       -- pid
  GROUP BY pid
)
SELECT 
  prod.product_id,                              -- prod
  prod.name,
  prod.price,
  prod.colour,
  IFNULL(ventas.total_sold, 0) AS total_sold    -- ventas
FROM sprint3_silver.products_clean prod         -- prod
LEFT JOIN ventas_por_producto ventas            -- ventas
  ON prod.product_id = ventas.product_id;

-- Ejercicio 3: Exportación de Resultados

SELECT *
FROM sprint3_gold.product_sales_ranking
ORDER BY total_sold DESC;