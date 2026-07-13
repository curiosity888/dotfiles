# SQL — BigQuery / PostgreSQL

## Оконные функции

```sql
-- ранжирование
ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time)   -- 1,2,3,4
RANK()       OVER (...)   -- 1,2,2,4 (с пропусками)
DENSE_RANK() OVER (...)   -- 1,2,2,3 (без пропусков)

-- соседние строки
LAG(revenue)  OVER (PARTITION BY user_id ORDER BY dt)          -- предыдущая
LEAD(revenue, 2, 0) OVER (...)                                 -- через одну, default 0

-- агрегаты по окну
SUM(revenue) OVER (PARTITION BY user_id ORDER BY dt)           -- накопительный
AVG(revenue) OVER (ORDER BY dt ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)  -- скользящее 7д

FIRST_VALUE(source) OVER (PARTITION BY user_id ORDER BY dt)    -- первый источник
NTILE(10) OVER (ORDER BY ltv)                                  -- децили
```

**QUALIFY** (BQ) — фильтр по окну без подзапроса:

```sql
SELECT * FROM events
QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time) = 1
```

В Postgres QUALIFY нет — оборачивай в подзапрос/CTE.

## Даты

| Задача | BigQuery | PostgreSQL |
|---|---|---|
| Сегодня | `CURRENT_DATE()` | `CURRENT_DATE` |
| Усечь до недели | `DATE_TRUNC(dt, WEEK(MONDAY))` | `DATE_TRUNC('week', dt)` |
| Разница дней | `DATE_DIFF(d2, d1, DAY)` | `d2 - d1` |
| Добавить период | `DATE_ADD(dt, INTERVAL 7 DAY)` | `dt + INTERVAL '7 days'` |
| Из timestamp | `DATE(ts)` | `ts::date` |
| Из unix-секунд | `TIMESTAMP_SECONDS(x)` | `TO_TIMESTAMP(x)` |
| Форматирование | `FORMAT_DATE('%Y-%m', dt)` | `TO_CHAR(dt, 'YYYY-MM')` |
| Часть даты | `EXTRACT(DAYOFWEEK FROM dt)` | `EXTRACT(DOW FROM dt)` |

Внимание: DAYOFWEEK в BQ — 1=воскресенье; DOW в PG — 0=воскресенье.

## NULL

```sql
COALESCE(a, b, 0)         -- первый не-NULL
NULLIF(a, 0)              -- NULL, если a=0 (защита деления: x / NULLIF(y,0))
IFNULL(a, 0)              -- BQ; в PG только COALESCE

COUNT(*)                  -- все строки
COUNT(col)                -- без NULL
COUNT(DISTINCT col)       -- уникальные без NULL

-- NULL не равен ничему: WHERE col != 'x' ПРОПУСТИТ строки с NULL
WHERE col IS DISTINCT FROM 'x'   -- PG: учитывает NULL
WHERE col != 'x' OR col IS NULL  -- универсально
```

## Строки

| Задача | BigQuery | PostgreSQL |
|---|---|---|
| Подстрока | `SUBSTR(s, 1, 3)` | `SUBSTR(s, 1, 3)` |
| Разбить | `SPLIT(s, ',')` → array | `SPLIT_PART(s, ',', 1)` → элемент |
| Regex-извлечение | `REGEXP_EXTRACT(s, r'id=(\d+)')` | `SUBSTRING(s FROM 'id=(\d+)')` |
| Regex-проверка | `REGEXP_CONTAINS(s, r'^ru_')` | `s ~ '^ru_'` |
| Склейка | `CONCAT(a, '-', b)` или `a \|\| '-' \|\| b` | то же |
| Агрегация в строку | `STRING_AGG(name, ', ' ORDER BY dt)` | то же |

## Массивы и структуры (BQ)

```sql
ARRAY_AGG(event ORDER BY ts LIMIT 10)       -- собрать массив
ARRAY_LENGTH(arr)

-- развернуть массив в строки
SELECT user_id, e
FROM t, UNNEST(events) AS e                  -- CROSS JOIN UNNEST

-- элемент массива
arr[OFFSET(0)]   -- с 0, ошибка если пусто
arr[SAFE_OFFSET(0)]  -- NULL если пусто
```

## Полезные паттерны

```sql
-- дедупликация: последняя запись по ключу
SELECT * FROM t
QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1

-- ретеншн день N
SELECT DATE_DIFF(e.dt, u.install_date, DAY) AS day_n,
       COUNT(DISTINCT e.user_id) / COUNT(DISTINCT u.user_id) AS retention
...

-- pivot через условные агрегаты
SUM(IF(platform = 'ios', revenue, 0)) AS revenue_ios       -- BQ
SUM(revenue) FILTER (WHERE platform = 'ios')               -- PG

-- защита от деления на ноль
SAFE_DIVIDE(a, b)          -- BQ: NULL вместо ошибки
a / NULLIF(b, 0)           -- PG
```

## Порядок выполнения (почему alias не виден в WHERE)

`FROM → JOIN → WHERE → GROUP BY → HAVING → SELECT → QUALIFY → ORDER BY → LIMIT`

Alias из SELECT доступен в `QUALIFY`/`ORDER BY` (и в `GROUP BY`/`HAVING` в BQ), но не в `WHERE`.
