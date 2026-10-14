import firebase_admin
from firebase_admin import firestore
import json
from main import generate_charging_plan_logic, compute_cold_weather_battery_limits

db = firestore.client()

print("--- Testing Cold Weather Limits ---")
print("Temp 1.0C (Cold):", compute_cold_weather_battery_limits(1.0))
print("Temp 3.5C (Spring Mild):", compute_cold_weather_battery_limits(3.5, 100))
print("Temp 7.0C (Warm):", compute_cold_weather_battery_limits(7.0))

print("\n--- Testing Live AI Plan Generation ---")
plan = generate_charging_plan_logic(db)
print("Plan Status:", plan.get("status"))
print("Calculated Target SoC:", plan.get("target_soc"))
print("Charge kWh:", plan.get("charge_kwh"))
print("Tasks Generated:")
print(json.dumps(plan.get("suggested_tasks"), indent=2))
print("Reasoning:")
for r in plan.get("reasoning", []):
    print(" -", r)
