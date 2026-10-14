import firebase_admin
from firebase_admin import firestore
import json
import requests
from tesla_fleet import ensure_valid_tesla_token

firebase_admin.initialize_app()
db = firestore.client()

cfg = db.collection("settings").document("tesla").get().to_dict()
access_token = ensure_valid_tesla_token(db, cfg)

url = "https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/vehicles"
headers = {
    "Authorization": f"Bearer {access_token}",
    "Content-Type": "application/json"
}

print("Fetching vehicles with raw response...")
response = requests.get(url, headers=headers)
print(f"Status Code: {response.status_code}")
print("Response Text:")
print(response.text)
