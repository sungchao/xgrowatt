# ml/ — 数据集导出与 PV 模型训练

本地脚本,不部署到云端。依赖:

```bash
pip3 install pandas numpy scikit-learn firebase-admin --break-system-packages
```

## 用法

```bash
cd /Users/xx/Documents/XGrowatt/ml

# 1. 从 Firestore 导出数据集(可随时重跑,全量重建)
python3 export_dataset.py ~/Downloads/xgrowatt-key.json --days 90

# 2. 训练(--capacity-kw = 光伏装机容量,本系统为 6.6 kW)
python3 train_pv_model.py --data-dir data --capacity-kw 6.6

# 3. 部署模型 = 把系数写入 Firestore status/pv_model(仅当模型赢过 baseline 时允许)
python3 upload_model.py ~/Downloads/xgrowatt-key.json
```

## 产物

| 文件 | 内容 |
|---|---|
| `data/telemetry_30min.csv` | 遥测重采样到 30 分钟网格 + 实测天气 |
| `data/forecast_long.csv` | 预报快照展开:(issued_at, target_time, horizon_h, 天气特征) |
| `data/train_forecast.csv` | 预报特征 join 实测 PV/负载,主训练表 |
| `data/pv_model_coefficients.json` | 岭回归系数(raw 空间,推理只需点积)+ MAE/RMSE + baseline 对比 |

## 两个模型变体

- **actual**:实测天气 → 实测 PV。可预测性上限,部署前的 sanity check。
- **forecast**:预报天气 + horizon_h → 实测 PV。真正要部署的模型(推理时输入就是预报)。两者差距 = 预报误差的代价。

## 判断标准与上线/回滚

- `upload_model.py` 会打印模型 vs baseline 经验公式的 MAE 对比,**只有模型赢(`recommended: ridge`)才允许上传**(`--force` 可跳过)。上传 = 写 Firestore `status/pv_model` 一个文档,云函数下次运行(23:10 或 App 手动刷新)自动切换,`charging_plan.model_used` 从 `empirical_formula` 变 `ridge` 即生效。
- **回滚**:Firestore 控制台删掉 `status/pv_model` 文档,立刻退回经验公式,无需部署。
- **重训节奏**:每周重跑三条命令一次,让模型跟上季节变化和数据积累;指标持续变好是正常曲线。
- 训练行数 < 200(约 2 周白天数据)时脚本会警告,此阶段 baseline 可能更稳,继续攒数据。
- 测试集按"最后 20% 日历天"切分,不随机切(相邻半小时强自相关,随机切会泄漏、虚高指标)。
- 覆盖率不足 50% 的特征自动剔除(如未回填 GTI 的老数据),控制台会打印被剔除的列。

## 特征说明

模型特征:`global_tilted_irradiance_wm2`(倾斜面辐照度,板面 25° 朝北,最强单特征)、GHI/直射/散射/DNI 四个辐照量、气温、is_day、hour/doy 的 sin/cos 时间编码;forecast 变体额外带 `horizon_h`(预报时距)。推理是纯点积:`pred = max(0, intercept + Σ coef·x)`,云端无需 ML 库。

注意:`data/` 和 service account key 不要提交 git。
