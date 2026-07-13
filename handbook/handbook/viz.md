# Визуализация — matplotlib / seaborn

Правило: строишь через seaborn, допиливаешь через matplotlib (`ax`).
Seaborn хочет pandas — из polars сначала `df.to_pandas()`.

## Каркас: всегда работай с ax

```python
import matplotlib.pyplot as plt
import seaborn as sns

fig, ax = plt.subplots(figsize=(10, 5))
sns.lineplot(data=df, x="dt", y="revenue", hue="platform", ax=ax)
ax.set(title="Revenue by platform", xlabel="", ylabel="Revenue, $")
fig.tight_layout()

# сетка графиков
fig, axes = plt.subplots(2, 2, figsize=(12, 8), sharex=True)
sns.lineplot(..., ax=axes[0, 0])
```

## Типовые графики аналитика

```python
# динамика метрики + разбивка
sns.lineplot(data=df, x="dt", y="dau", hue="platform", marker="o")

# распределение: гистограмма / ecdf (ecdf честнее для LTV и прочих skewed)
sns.histplot(data=df, x="ltv", bins=50, log_scale=(True, False))
sns.ecdfplot(data=df, x="ltv", hue="cohort")

# сравнение групп
sns.barplot(data=df, x="segment", y="arpu", errorbar=("ci", 95))   # с довинтервалом
sns.boxplot(data=df, x="segment", y="session_len", showfliers=False)
sns.violinplot(...)                          # box + распределение

# ретеншн-матрица когорт
pivot = df.pivot(index="cohort", columns="day_n", values="retention")
sns.heatmap(pivot, annot=True, fmt=".0%", cmap="Blues", vmin=0, vmax=0.6)

# scatter с прозрачностью для больших выборок
sns.scatterplot(data=df, x="sessions", y="revenue", alpha=0.2, s=10)
```

## Мелкие мультипанели (аналог facet в BI)

```python
g = sns.relplot(data=df, x="dt", y="revenue",
                col="country", col_wrap=3, kind="line",
                height=3, aspect=1.5)
g.set_titles("{col_name}")
```

## Оси, даты, проценты

```python
import matplotlib.dates as mdates
from matplotlib.ticker import PercentFormatter, FuncFormatter

ax.xaxis.set_major_locator(mdates.WeekdayLocator(byweekday=0))   # тики по понедельникам
ax.xaxis.set_major_formatter(mdates.DateFormatter("%d %b"))
fig.autofmt_xdate()                                              # повернуть подписи

ax.yaxis.set_major_formatter(PercentFormatter(1.0))              # 0.42 → 42%
ax.yaxis.set_major_formatter(FuncFormatter(lambda x, _: f"{x/1e6:.1f}M"))

ax.set_ylim(0, None)          # bar/area всегда от нуля — иначе врёт
ax.set_yscale("log")
ax.axhline(0.4, ls="--", c="gray")            # таргет-линия
ax.axvspan("2026-07-01", "2026-07-08", alpha=0.1, color="red")   # период события
```

## Подписи и легенда

```python
ax.legend(title="", frameon=False, loc="upper left")
sns.move_legend(ax, "upper left", bbox_to_anchor=(1, 1))   # вынести за график

ax.annotate("релиз 2.0", xy=(x, y), xytext=(x, y * 1.2),
            arrowprops=dict(arrowstyle="->"))

for c in ax.containers:                        # значения на барах
    ax.bar_label(c, fmt="%.1f")
```

## Стиль один раз в начале ноутбука

```python
sns.set_theme(style="whitegrid", palette="deep", rc={"figure.figsize": (10, 5)})
sns.despine()                 # убрать рамку сверху/справа

# свои цвета под платформы — фиксируй словарём, чтобы не плясали между графиками
palette = {"ios": "#555555", "android": "#3ddc84"}
sns.lineplot(..., hue="platform", palette=palette)
```

## Сохранение

```python
fig.savefig("chart.png", dpi=150, bbox_inches="tight")
fig.savefig("chart.svg")      # вектор для презентаций
```

## Грабли

- seaborn не понимает polars надёжно — конверти в pandas сам;
- `plt.plot` в цикле по группам = каша, используй `hue`;
- `barplot` по умолчанию рисует mean с бутстрап-CI — на больших данных
  медленно (`errorbar=None` если CI не нужен);
- даты в matplotlib должны быть datetime, не строками — иначе тики съедут;
- в jupyter фигура рисуется сама, `plt.show()` не нужен; но если фигур
  в ячейке несколько — закрывай лишние `plt.close(fig)`.
