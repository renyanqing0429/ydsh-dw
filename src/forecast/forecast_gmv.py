# -*- coding: utf-8 -*-
"""
第 3 周 子任务 2：每日 GMV 时间序列分析与预测建模
--------------------------------------------------
数据源：dashboard/data/ads_daily_trend.tsv（ADS ads_daily_trend 全年 366 天导出）
技术栈：pandas + scikit-learn（任务书指定），不依赖 Hive 在线（离线可复跑）。
流程：
  1. 读取数据 → 日 GMV 序列（含订单量/买家数/客单价）
  2. 趋势分析：7 日 / 30 日移动平均、月度汇总、月环比
  3. 特征工程：lag1 / lag7 / ma7 / ma14 / 星期几
  4. 建模：线性回归（任务书主模型）vs 朴素基线（昨日值）vs MA7 基线
  5. 评估：滚动留出最后 7 天做验证，MAE / MAPE / RMSE
  6. 预测：递归多步预测未来 7 天 GMV
输出：
  src/forecast/output/forecast_result.json   指标与预测值
  src/forecast/output/forecast_plot.png      历史 + 预测对比图
用法：python src/forecast/forecast_gmv.py
"""
import json
import os
import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(BASE, "dashboard", "data", "ads_daily_trend.tsv")
OUT = os.path.join(BASE, "src", "forecast", "output")
HORIZON = 7  # 任务书要求：预测未来 7 天


def load_series() -> pd.DataFrame:
    df = pd.read_csv(DATA, sep="\t")
    df.columns = [c.split(".")[-1] for c in df.columns]  # 去掉 ads_daily_trend. 前缀
    df["dt"] = pd.to_datetime(df["dt"])
    df = df.sort_values("dt").reset_index(drop=True)
    return df[["dt", "gmv", "order_cnt", "buyer_cnt", "aov"]]


def add_features(df: pd.DataFrame) -> pd.DataFrame:
    d = df.copy()
    d["lag1"] = d["gmv"].shift(1)
    d["lag7"] = d["gmv"].shift(7)
    d["ma7"] = d["gmv"].rolling(7).mean()
    d["ma14"] = d["gmv"].rolling(14).mean()
    d["dow"] = d["dt"].dt.day_of_week
    return d.dropna().reset_index(drop=True)


FEATURES = ["lag1", "lag7", "ma7", "ma14", "dow"]


def walk_forward_eval(train_df: pd.DataFrame, n_test: int = HORIZON):
    """滚动验证：留出最后 n_test 天，逐日滚动预测（预测特征用真实历史更新）。"""
    d = add_features(train_df)
    test = d.tail(n_test).copy()
    hist = df_all[train_df["dt"] <= test.iloc[0]["dt"] - pd.Timedelta(days=1)].copy()

    preds, actuals, dates = [], [], []
    model = LinearRegression()
    fit_d = d.head(len(d) - n_test)
    model.fit(fit_d[FEATURES], fit_d["gmv"])

    for i in range(n_test):
        row_dt = test.iloc[i]["dt"]
        h = hist.copy()
        lag1 = h["gmv"].iloc[-1]
        lag7 = h["gmv"].iloc[-7] if len(h) >= 7 else lag1
        ma7 = h["gmv"].tail(7).mean()
        ma14 = h["gmv"].tail(14).mean() if len(h) >= 14 else ma7
        x = pd.DataFrame([{"lag1": lag1, "lag7": lag7, "ma7": ma7, "ma14": ma14,
                           "dow": row_dt.day_of_week}])[FEATURES]
        p = float(model.predict(x)[0])
        preds.append(p)
        actuals.append(float(test.iloc[i]["gmv"]))
        dates.append(str(row_dt.date()))
        hist = pd.concat([hist, pd.DataFrame([{"dt": row_dt, "gmv": actuals[-1]}])],
                         ignore_index=True)

    return dates, np.array(actuals), np.array(preds)


def recursive_forecast(train_df: pd.DataFrame, horizon: int = HORIZON):
    """递归多步预测未来 horizon 天（预测值回填作为后续 lag/ma 特征）。"""
    model = LinearRegression()
    d = add_features(train_df)
    model.fit(d[FEATURES], d["gmv"])

    hist = train_df[["dt", "gmv"]].copy()
    results = []
    for i in range(horizon):
        next_dt = hist["dt"].iloc[-1] + pd.Timedelta(days=1)
        x = pd.DataFrame([{
            "lag1": hist["gmv"].iloc[-1],
            "lag7": hist["gmv"].iloc[-7],
            "ma7": hist["gmv"].tail(7).mean(),
            "ma14": hist["gmv"].tail(14).mean(),
            "dow": next_dt.day_of_week,
        }])[FEATURES]
        p = float(model.predict(x)[0])
        results.append({"date": str(next_dt.date()), "pred_gmv": round(p, 2)})
        hist = pd.concat([hist, pd.DataFrame([{"dt": next_dt, "gmv": p}])],
                         ignore_index=True)
    return results, model


def main():
    global df_all
    df_all = load_series()
    os.makedirs(OUT, exist_ok=True)

    # ---------- 1. 趋势分析 ----------
    df_all["ma7"] = df_all["gmv"].rolling(7).mean()
    df_all["ma30"] = df_all["gmv"].rolling(30).mean()
    monthly = df_all.set_index("dt")["gmv"].resample("MS").sum().round(2)
    mom = monthly.pct_change().mul(100).round(2)

    trend = {
        "data_days": int(len(df_all)),
        "date_start": str(df_all["dt"].iloc[0].date()),
        "date_end": str(df_all["dt"].iloc[-1].date()),
        "total_gmv": round(float(df_all["gmv"].sum()), 2),
        "daily_mean": round(float(df_all["gmv"].mean()), 2),
        "daily_std": round(float(df_all["gmv"].std()), 2),
        "cv_pct": round(float(df_all["gmv"].std() / df_all["gmv"].mean() * 100), 2),
        "monthly_gmv": {str(k.date())[:7]: float(v) for k, v in monthly.items()},
        "monthly_mom_pct": {str(k.date())[:7]: (None if pd.isna(v) else float(v))
                            for k, v in mom.items()},
    }

    # ---------- 2. 滚动验证（最后 7 天留出） ----------
    dates, actuals, preds = walk_forward_eval(df_all, HORIZON)
    base_naive_pred = df_all["gmv"].shift(1).iloc[-HORIZON:].values
    base_ma7_pred = df_all["gmv"].rolling(7).mean().shift(1).iloc[-HORIZON:].values

    def metrics(a, p):
        return {
            "MAE": round(float(mean_absolute_error(a, p)), 2),
            "RMSE": round(float(np.sqrt(mean_squared_error(a, p))), 2),
            "MAPE_pct": round(float(np.mean(np.abs((a - p) / a)) * 100), 2),
        }

    eval_result = {
        "eval_window": {"start": dates[0], "end": dates[-1], "days": HORIZON},
        "linear_regression": metrics(actuals, preds),
        "baseline_naive(yesterday)": metrics(actuals, base_naive_pred),
        "baseline_ma7": metrics(actuals, base_ma7_pred),
        "detail": [{"date": d, "actual": round(a, 2), "pred": round(p, 2)}
                   for d, a, p in zip(dates, actuals, preds)],
    }

    # ---------- 3. 未来 7 天递归预测 ----------
    forecast, model = recursive_forecast(df_all, HORIZON)
    coefs = dict(zip(FEATURES, [round(float(c), 1) for c in model.coef_]))

    result = {
        "model": "LinearRegression(lag1, lag7, ma7, ma14, dow)",
        "trend": trend,
        "evaluation": eval_result,
        "forecast_7d": forecast,
        "coef": coefs,
        "intercept": round(float(model.intercept_), 1),
    }
    with open(os.path.join(OUT, "forecast_result.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    # ---------- 4. 可视化 ----------
    fig, ax = plt.subplots(figsize=(12, 5.5))
    ax.plot(df_all["dt"], df_all["gmv"], color="#9aa5b1", lw=0.8, alpha=0.7, label="日 GMV")
    ax.plot(df_all["dt"], df_all["ma7"], color="#1f6feb", lw=1.6, label="7 日移动平均")
    f_dates = [pd.Timestamp(x["date"]) for x in forecast]
    f_vals = [x["pred_gmv"] for x in forecast]
    ax.plot([df_all["dt"].iloc[-1]] + f_dates,
            [df_all["gmv"].iloc[-1]] + f_vals,
            color="#d1242f", lw=2, marker="o", ms=4, label="未来 7 天预测")
    ax.set_title("每日 GMV 时间序列与未来 7 天预测（线性回归 lag+MA 特征）")
    ax.set_ylabel("GMV（元）")
    ax.legend()
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "forecast_plot.png"), dpi=150)

    # 控制台摘要
    print("== 趋势 ==")
    print(f"  全年 GMV {trend['total_gmv']:,} 元，日均 {trend['daily_mean']:,}，"
          f"波动系数 CV={trend['cv_pct']}%")
    print("== 验证（最后 7 天留出）==")
    for k in ("linear_regression", "baseline_naive(yesterday)", "baseline_ma7"):
        print(f"  {k:28s} {eval_result[k]}")
    print("== 未来 7 天预测 ==")
    for x in forecast:
        print(f"  {x['date']}  {x['pred_gmv']:>12,.2f}")
    print(f"\n输出：{OUT}")


if __name__ == "__main__":
    sys.exit(main())
