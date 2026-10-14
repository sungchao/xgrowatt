import firebase_admin
from firebase_admin import firestore

firebase_admin.initialize_app()
db = firestore.client()
doc = db.collection("status").document("tesla_live").get()
if doc.exists:
    d = doc.to_dict()
    print("Tesla Live document found!")
    print("Last updated:", d.get("last_updated"))
    print("Note:", d.get("note"))
else:
    print("No status/tesla_live document found.")
