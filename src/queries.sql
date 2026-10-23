-- Purchase-to-Pay (BPI Challenge 2019) : requêtes d'exploration (DuckDB)

CREATE OR REPLACE VIEW events AS
SELECT * FROM read_parquet('data/bpi2019.parquet');

-- Nettoyage : on exclut les cas contenant un événement daté avant 2017
CREATE OR REPLACE VIEW events_clean AS
SELECT * FROM events
WHERE "case:concept:name" NOT IN (
    SELECT DISTINCT "case:concept:name"
    FROM events
    WHERE "time:timestamp" < TIMESTAMPTZ '2017-01-01'
);

-- 1. Vue d'ensemble
SELECT COUNT(*) AS events,
       COUNT(DISTINCT "case:concept:name") AS cases,
       COUNT(DISTINCT "concept:name") AS activities,
       COUNT(DISTINCT "case:Vendor") AS vendors
FROM events_clean;

-- 2. Fréquence des activités
SELECT "concept:name" AS activity,
       COUNT(*) AS n,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM events_clean
GROUP BY 1
ORDER BY n DESC;

-- 3. Durée des cas (jours)
WITH c AS (
  SELECT "case:concept:name" AS case_id,
         MIN("time:timestamp") AS start_ts,
         MAX("time:timestamp") AS end_ts
  FROM events_clean GROUP BY 1
)
SELECT COUNT(*) AS cases,
       MEDIAN(date_diff('day', start_ts, end_ts)) AS median_days,
       quantile_cont(date_diff('day', start_ts, end_ts), 0.9) AS p90_days,
       MAX(date_diff('day', start_ts, end_ts)) AS max_days
FROM c;

-- 4. Temps d'attente entre étapes (goulots candidats)
WITH ordered AS (
  SELECT "case:concept:name" AS case_id,
         "concept:name" AS activity,
         "time:timestamp" AS ts,
         LAG("concept:name") OVER (PARTITION BY "case:concept:name" ORDER BY "time:timestamp") AS prev_activity,
         LAG("time:timestamp") OVER (PARTITION BY "case:concept:name" ORDER BY "time:timestamp") AS prev_ts
  FROM events_clean
)
SELECT prev_activity, activity,
       COUNT(*) AS n,
       ROUND(MEDIAN(date_diff('second', prev_ts, ts)) / 86400.0, 1) AS median_days,
       ROUND(quantile_cont(date_diff('second', prev_ts, ts), 0.9) / 86400.0, 1) AS p90_days
FROM ordered
WHERE prev_activity IS NOT NULL
GROUP BY 1, 2
HAVING COUNT(*) >= 1000
ORDER BY n * median_days DESC
LIMIT 15;