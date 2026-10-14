import firebase_admin
from firebase_admin import credentials, firestore
import datetime
import time

firebase_admin.initialize_app()
db = firestore.client()
doc = db.collection('settings').document('tesla').get()
d = doc.to_dict()

expires_at = d.get('expires_at')
now_ts = int(time.time())
print(f"Token expired? {now_ts >= expires_at} (expires_at={expires_at}, now={now_ts})")
print(f"Has private key: {'Yes' if d.get('private_key_pem') else 'No'}")
