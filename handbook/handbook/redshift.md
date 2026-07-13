# SQL — Amazon Redshift

Диалект вырос из PostgreSQL 8: почти весь PG-синтаксис работает,
но агрегаты/даты/JSON — свои. Ниже отличия, о которые спотыкаешься после BQ/PG.

## Оконные функции

```sql
-- ранжирование/соседи/агрегаты — как везде
ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time)
LAG(revenue) OVER (PARTITION BY user_id ORDER BY dt)
SUM(revenue) OVER (PARTITION BY user_id ORDER BY dt
                   ROWS UNBOUNDED PRECEDING)              -- накопительный
AVG(revenue) OVER (ORDER BY dt ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
NTILE(10) OVER (ORDER BY ltv)
```

**QUALIFY поддерживается** (с 2023) — как в BQ:

```sql
SELECT * FROM events
QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time) = 1
```

Нюанс: для `SUM/AVG OVER (ORDER BY ...)` Redshift требует явный frame (`ROWS ...`),
иначе ошибка — в отличие от BQ/PG, где есть default.

## Даты

| Задача | Redshift | Отличие от BQ |
|---|---|---|
| Сегодня / сейчас | `CURRENT_DATE` / `GETDATE()` | без скобок / вместо `CURRENT_TIMESTAMP()` |
| Усечь до недели | `DATE_TRUNC('week', dt)` | неделя всегда с понедельника |
| Разница дней | `DATEDIFF(day, d1, d2)` | порядок аргументов обратный BQ! |
| Добавить период | `DATEADD(day, 7, dt)` | — |
| Из timestamp | `ts::date` | вместо `DATE(ts)` |
| Из unix-секунд | `TIMESTAMP 'epoch' + x * INTERVAL '1 second'` | функции нет, только трюк |
| Форматирование | `TO_CHAR(dt, 'YYYY-MM')` | как в PG |
| Часть даты | `EXTRACT(DOW FROM dt)` | 0=воскресенье (в BQ 1=воскресенье) |

**Ловушка DATEDIFF**: считает пересечения границ, а не полные периоды:
`DATEDIFF(month, '2024-01-31', '2024-02-01') = 1`.

## NULL

```sql
COALESCE(a, b, 0)         -- первый не-NULL
NVL(a, 0)                 -- синоним COALESCE (наследие Oracle)
NVL2(a, x, y)             -- x если a не NULL, иначе y
NULLIF(a, 0)              -- NULL, если a=0

-- NULL не равен ничему: WHERE col != 'x' ПРОПУСТИТ строки с NULL
WHERE col != 'x' OR col IS NULL

DECODE(a, b, 'eq', 'ne')  -- единственное место, где NULL == NULL
```

## Строки

```sql
SUBSTRING(s, 1, 3)
SPLIT_PART(s, ',', 1)                        -- элемент, как в PG
REGEXP_SUBSTR(s, 'id=([0-9]+)', 1, 1, 'e')   -- 'e' = вернуть группу, не весь матч
REGEXP_COUNT(s, 'pattern')                   -- проверка: > 0
s ~ '^ru_'                                   -- regex-матч, как в PG
CONCAT(a, b) / a || '-' || b                 -- CONCAT только 2 аргумента!

-- агрегация в строку: НЕ STRING_AGG
LISTAGG(name, ', ') WITHIN GROUP (ORDER BY dt)
LISTAGG(DISTINCT name, ', ')
```

## JSON / SUPER (вместо массивов BQ)

```sql
-- json в varchar-колонке
JSON_EXTRACT_PATH_TEXT(payload, 'params', 'level')   -- '' если нет ключа

-- тип SUPER: навигация точкой, как в BQ struct
SELECT data.user.id, data.items[0].name FROM t

-- развернуть SUPER-массив в строки (аналог UNNEST)
SELECT t.user_id, item
FROM t, t.data.items AS item
```

## Полезные паттерны

```sql
-- дедупликация: последняя запись по ключу
SELECT * FROM t
QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1

-- pivot: FILTER из PG не работает, только CASE (или нативный PIVOT)
SUM(CASE WHEN platform = 'ios' THEN revenue ELSE 0 END) AS revenue_ios

-- деление: int/int = int (5/2 = 2)! и SAFE_DIVIDE нет
revenue * 1.0 / NULLIF(installs, 0)

-- ретеншн день N
SELECT DATEDIFF(day, u.install_date, e.dt) AS day_n,
       COUNT(DISTINCT e.user_id) * 1.0 / COUNT(DISTINCT u.user_id) AS retention
...
```

## Специфика Redshift

- `DISTKEY` / `SORTKEY` таблицы решают скорость join/фильтров.
  В `EXPLAIN` плохой знак — `DS_DIST_BOTH` / `DS_BCAST_INNER` (перераспределение данных).
- Размер и skew таблиц: `SELECT * FROM svv_table_info ORDER BY size DESC`.
- История запросов: `SYS_QUERY_HISTORY` (свои) или спросить DBA про WLM-очереди,
  если запрос висит в queued.
- `LIMIT` не удешевляет запрос как в BQ — скан всё равно колоночный по нужным полям;
  но `SELECT *` по широкой таблице всё так же дорого.

## Порядок выполнения

`FROM → JOIN → WHERE → GROUP BY → HAVING → SELECT → QUALIFY → ORDER BY → LIMIT`

Alias из SELECT не виден в WHERE, но Redshift умеет lateral alias:
`SELECT a+b AS s, s*2 AS s2` — можно ссылаться на alias в том же SELECT
и в GROUP BY.
