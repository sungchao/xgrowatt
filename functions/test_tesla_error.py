import firebase_admin
from firebase_admin import firestore
import json
from tesla_fleet import smart_poll_tesla, ensure_valid_tesla_token, TeslaFleetClient

firebase_admin.initialize_app()
db = firestore.client()

print("Fetching Tesla status...")
try:
    res = smart_poll_tesla(db)
    print("Success:")
    print(json.dumps(res, indent=2))
except Exception as e:
    print(f"Error occurred: {str(e)}")

# Also try fetching vehicles directly to see raw API response
print("\n--- Direct API Check ---")
cfg = db.collection("settings").document("tesla").get().to_dict()
try:
    access_token = ensure_valid_tesla_token(db, cfg)
    client = TeslaFleetClient(client_id=cfg.get("client_id", ""), client_secret=cfg.get("client_secret", ""))
    print("Token is valid. Fetching vehicles...")
    vehicles = client.get_vehicles(access_token)
    print("Vehicles response:")
    print(json.dumps(vehicles, indent=2))
except Exception as e:
    print(f"Direct API Error: {str(e)}")
