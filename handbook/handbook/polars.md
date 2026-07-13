# Polars

Ключевая идея: всё — выражения (`pl.col(...)`), они компонуются и
оптимизируются, циклов и apply почти никогда не нужно.

## Базовые операции

```python
import polars as pl

df.select("user_id", "revenue")                  # только колонки
df.select(pl.col("^rev_.*$"))                    # по regex
df.filter(pl.col("platform") == "ios")
df.filter(pl.col("dt").is_between(d1, d2))
df.with_columns(                                 # добавить/заменить колонки
    arpu=pl.col("revenue") / pl.col("users"),
    dt=pl.col("ts").dt.date(),
)
df.sort("dt", descending=True)
df.rename({"old": "new"})
df.drop("tmp")
df["revenue"]                                    # → Series
```

## group_by / agg

```python
df.group_by("platform").agg(
    pl.col("revenue").sum(),
    pl.col("user_id").n_unique().alias("users"),
    pl.col("revenue").filter(pl.col("is_payer")).mean().alias("arppu"),  # условный агрегат
    pl.len().alias("rows"),
)

# группировка по датам с шагом (аналог resample из pandas)
df.group_by_dynamic("ts", every="1w").agg(pl.col("revenue").sum())
```

## Окна: over вместо оконных функций SQL

```python
df.with_columns(
    pl.col("revenue").sum().over("user_id").alias("user_total"),
    pl.col("ts").rank().over("user_id").alias("event_n"),          # ROW_NUMBER ≈ rank("ordinal")
    pl.col("revenue").shift(1).over("user_id").alias("prev"),      # LAG
    pl.col("revenue").cum_sum().over("user_id").alias("running"),  # накопительный
    pl.col("revenue").rolling_mean(7).alias("ma7"),                # скользящее (по строкам)
)

# первая запись на пользователя (дедуп)
df.sort("ts").group_by("user_id").first()
# или: df.unique(subset="user_id", keep="first")  — но сортируй заранее
```

## if/else и категоризация

```python
pl.when(pl.col("rev") > 100).then(pl.lit("whale"))
  .when(pl.col("rev") > 0).then(pl.lit("payer"))
  .otherwise(pl.lit("free"))
  .alias("segment")

pl.col("country").replace_strict({"RU": "ru", "US": "us"}, default="other")
pl.col("ltv").cut([0, 10, 100], labels=["zero", "low", "mid", "high"])
```

## Даты и строки

```python
pl.col("ts").dt.date() / .dt.truncate("1w") / .dt.weekday()   # 1=понедельник
(pl.col("d2") - pl.col("d1")).dt.total_days()
pl.col("s").str.to_date("%Y-%m-%d")

pl.col("s").str.contains(r"^ru_")            # regex
pl.col("s").str.extract(r"id=(\d+)", 1)
pl.col("s").str.split(",")                   # → список
pl.col("s").str.slice(0, 3)
```

## NULL

```python
pl.col("a").fill_null(0)                     # NaN != null! для float ещё fill_nan
pl.col("a").is_null() / .is_not_null()
df.drop_nulls(subset=["user_id"])
pl.coalesce("a", "b", pl.lit(0))
```

## Join / concat

```python
df.join(other, on="user_id", how="left")     # inner/left/full/semi/anti
df.join(other, left_on="uid", right_on="user_id")
df.join_asof(events, on="ts", by="user_id")  # ближайший по времени (атрибуция)
pl.concat([df1, df2])                        # UNION ALL
```

## Lazy API — для больших файлов

```python
(
    pl.scan_parquet("events/*.parquet")      # scan_*, не read_*: ничего не читает
    .filter(pl.col("dt") >= "2026-07-01")    # predicate pushdown — прочтёт только нужное
    .group_by("platform").agg(pl.col("revenue").sum())
    .collect()                               # выполнение только здесь
)
df.lazy() ... .collect()                     # тот же трюк для DataFrame в памяти
lf.explain()                                 # план запроса (как EXPLAIN в SQL)
```

## Pivot / melt

```python
df.pivot(on="platform", index="dt", values="revenue", aggregate_function="sum")
df.unpivot(index="dt", on=["ios", "android"])   # длинный формат обратно
```

## Мосты в pandas-мир

```python
df.to_pandas()        # для seaborn/scipy
pl.from_pandas(pdf)
df.to_dicts()         # список словарей
```

Частые грабли после pandas: нет индекса (и это хорошо); `pl.len()` вместо
`count()` для размера группы; методы не мутируют df — всегда присваивай результат.
