# Growatt SPH Hybrid Inverter: Hardware Register Mapping Specification

This document provides the hardware register specifications, Modbus RS-485 / Cloud API array mappings, physical constraints, and firmware behaviors for the **Growatt SPH Series Hybrid Storage Inverters** (e.g. SPH 3000–10000TL3 BH-UP).

---

## 1. AC Forced Charge Parameter Array (`mix_ac_charge_time_period`)

When dispatching charging schedules to the inverter via the Growatt Cloud Open API or Modbus TCP/RS-485 bridge:
```python
api.update_mix_inverter_setting(device_sn, "mix_ac_charge_time_period", target_params)
```

`target_params` must be an ordered array of **18 string parameters**:

| Index | Parameter / Register | Type | Valid Range | Physical Semantics & Safety Rules |
|:---:|:---|:---:|:---:|:---|
| **0** | `chargePowerCommand` | String | `0`–`100` (%) | AC charge power percentage relative to rated inverter power (e.g., `100` = 5.0 kW / 10.0 kW). Automatically capped during cold ambient temperatures ($T_{\text{bat}} < 10^\circ\text{C}$). |
| **1** | `wchargeSOCLowLimit1` | String | `0`–`100` (%) | Target stop State of Charge (SoC). Once battery SoC reaches this threshold, AC charging halts. |
| **2** | `acChargeEnable` | String | `'0'` or `'1'` | **Global AC Charge Gate**. `'1'` permits AC charging from the grid; `'0'` strictly forbids grid energy imports. |
| **3** | `forcedChargeTimeStart1_H` | String | `'00'`–`23'` | Period 1 start hour (24h format). Reserved for overnight off-peak window (`'00'`). |
| **4** | `forcedChargeTimeStart1_M` | String | `'00'`–`59'` | Period 1 start minute (`'00'`). |
| **5** | `forcedChargeTimeStop1_H` | String | `'00'`–`23'` | Period 1 stop hour (`'06'`). |
| **6** | `forcedChargeTimeStop1_M` | String | `'00'`–`59'` | Period 1 stop minute (`'00'`). |
| **7** | `forcedChargeStopSwitch1` | String | `'0'` or `'1'` | **Period 1 Active Switch (`enable1`)**. `'1'` activates forced battery priority; `'0'` disables forced charge window. |
| **8** | `forcedChargeTimeStart2_H` | String | `'00'`–`23'` | Period 2 start hour. Reserved for weekend solar absorption window (`'12'`). |
| **9** | `forcedChargeTimeStart2_M` | String | `'00'`–`59'` | Period 2 start minute (`'00'`). |
| **10**| `forcedChargeTimeStop2_H` | String | `'00'`–`23'` | Period 2 stop hour (`'14'` or `'17'`). |
| **11**| `forcedChargeTimeStop2_M` | String | `'00'`–`59'` | Period 2 stop minute (`'00'`). |
| **12**| `forcedChargeStopSwitch2` | String | `'0'` or `'1'` | **Period 2 Active Switch (`enable2`)**. Controlled dynamically during negative price or calibration events. |
| **13**| `forcedChargeTimeStart3_H` | String | `'00'` | Period 3 start hour (Unused, fixed `'00'`). |
| **14**| `forcedChargeTimeStart3_M` | String | `'00'` | Period 3 start minute (Unused, fixed `'00'`). |
| **15**| `forcedChargeTimeStop3_H` | String | `'00'` | Period 3 stop hour (Unused, fixed `'00'`). |
| **16**| `forcedChargeTimeStop3_M` | String | `'00'` | Period 3 stop minute (Unused, fixed `'00'`). |
| **17**| `forcedChargeStopSwitch3` | String | `'0'` | Period 3 active switch (Unused, fixed `'0'`). |

---

## 2. Inverter Mode Priority Selector (`priorityChoose`)

The operational mode register dictates how solar generation, battery storage, and grid interaction are prioritized:

| Value | Mode Name | Behavior |
|:---:|:---|:---|
| `'0'` | **Load First (Default)** | PV powers home loads first. Any excess charges battery. If battery is full, excess exports to grid. When load exceeds PV, battery discharges to satisfy load before grid import. |
| `'1'` | **Battery First** | PV charges battery first up to target SoC. Discharging to local loads is inhibited. If AC charging is enabled (`acChargeEnable = '1'`), grid power is injected to reach target SoC. |
| `'2'` | **Grid First** | PV exports directly to grid first. Battery discharge can be scheduled to feed grid during peak feed-in tariff events. |

---

## 3. Dynamic Discharge Low Limit Register (`wdisChargeSOCLowLimit2`)

To enable high-current battery discharge to external loads (such as a 7 kW Tesla EV wall connector) while strictly protecting the household reserve:

- **Overnight Solar Sponge Window (00:00 – 06:00)**:
  `wdisChargeSOCLowLimit2` is programmed to `str(target_soc)` (e.g. `24`%). The inverter allows the home battery to discharge at up to 100% rated power (5.0 kW) to charge the vehicle, automatically cutting off when the battery reaches the target floor.
- **Daytime Normal Operation (06:00 – 23:59)**:
  At dawn (06:00 AEST), the system resets `wdisChargeSOCLowLimit2` back to `10`% (or physical hardware floor), making 100% of remaining battery capacity available to support household cooking, heating, and cooling loads.

---

## 4. Hardware EEPROM Protection Protocols

> [!CAUTION] **EEPROM Wear-out Prevention**
> Inverter microcontrollers utilize non-volatile EEPROM/Flash storage for operational registers. Excessive write cycles (> 100,000 writes) can permanently damage the onboard memory.

1. **Idempotent Write Caching**: Before dispatching any setting update, the cloud engine compares desired register states with the latest read-back telemetry cache. If parameters are identical, the network write is bypassed.
2. **Rate Limiting**: Write commands are throttled to a minimum interval of 15 minutes, with exceptions only for real-time safety trips or automated EV sponge floor reach events.
3. **Firmware Validation Check**: Every received response is checked against `errCode == 0` to verify physical write acknowledgement.
