from flask import Flask, request, jsonify
import uuid
from datetime import datetime, date

app = Flask(__name__)

# In-memory data storage
labels_db = {}
pickups_db = {}
tracking_db = {}

# Initial data
def initialize_data():
    # Initial Label and Tracking Info
    initial_label_id = str(uuid.uuid4())
    initial_tracking_number = "TN" + str(uuid.uuid4().hex)[:10].upper()
    labels_db[initial_label_id] = {
        "labelId": initial_label_id,
        "packageDimensions": "12x8x4",
        "packageWeight": 5.0,
        "recipientAddress": "123 Main St",
        "recipientCity": "Anytown",
        "recipientName": "Jane Doe",
        "recipientState": "CA",
        "recipientZip": "90210",
        "senderAddress": "456 Oak Ave",
        "senderCity": "Otherville",
        "senderName": "John Smith",
        "senderState": "NY",
        "senderZip": "10001",
        "shippingOptions": "priority",
        "trackingNumber": initial_tracking_number,
        "labelImage": "base64encodedimagestring==", # Placeholder
        "shippingCost": 15.75
    }
    tracking_db[initial_tracking_number] = {
        "trackingNumber": initial_tracking_number,
        "status": "In Transit",
        "estimatedDeliveryDate": (date.today().replace(day=date.today().day + 3)).isoformat(),
        "location": "Origin Scan Facility",
        "statusUpdates": [
            "Package received at origin facility",
            "Departed origin facility"
        ]
    }

    # Initial Pickup
    initial_pickup_id = str(uuid.uuid4())
    pickups_db[initial_pickup_id] = {
        "pickupId": initial_pickup_id,
        "contactName": "Alice Wonderland",
        "contactPhone": "555-1234",
        "pickupAddress": "789 Pine Ln",
        "pickupCity": "Pickupsburg",
        "pickupDate": (date.today().replace(day=date.today().day + 1)).isoformat(),
        "pickupState": "TX",
        "pickupTime": "14:30",
        "pickupZip": "75001",
        # Corresponds to inventorycheckresponse
        "sku": "ITEM001",
        "availableQuantity": 10,
        "location": "Warehouse A, Bay 3",
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

initialize_data()

# --- Helper Functions ---
def make_error(code, message, details=None, status_code=400):
    response = {
        "code": str(code),
        "message": message
    }
    if details:
        response["details"] = details
    return jsonify(response), status_code

# --- Routes ---

@app.route('/labels', methods=['POST'])
def generate_label():
    """
    Generates a shipping label.
    """
    if not request.is_json:
        return make_error("INVALID_REQUEST_FORMAT", "Request body must be JSON.", status_code=400)

    data = request.get_json()
    required_fields = [
        "packageDimensions", "packageWeight", "recipientAddress", "recipientCity",
        "recipientName", "recipientState", "recipientZip", "senderAddress",
        "senderCity", "senderName", "senderState", "senderZip", "shippingOptions"
    ]

    for field in required_fields:
        if field not in data:
            return make_error("MISSING_FIELD", f"Missing required field: {field}", status_code=400)

    try:
        label_id = str(uuid.uuid4())
        tracking_number = "TN" + str(uuid.uuid4().hex)[:10].upper() # Generate a unique tracking number

        new_label = {
            "labelId": label_id,
            "packageDimensions": data["packageDimensions"],
            "packageWeight": float(data["packageWeight"]),
            "recipientAddress": data["recipientAddress"],
            "recipientCity": data["recipientCity"],
            "recipientName": data["recipientName"],
            "recipientState": data["recipientState"],
            "recipientZip": data["recipientZip"],
            "senderAddress": data["senderAddress"],
            "senderCity": data["senderCity"],
            "senderName": data["senderName"],
            "senderState": data["senderState"],
            "senderZip": data["senderZip"],
            "shippingOptions": data["shippingOptions"],
            # Response fields
            "trackingNumber": tracking_number,
            "labelImage": f"base64encodedimage_{label_id}", # Placeholder
            "shippingCost": 20.50  # Placeholder cost
        }
        labels_db[label_id] = new_label

        # Create a corresponding tracking entry
        tracking_db[tracking_number] = {
            "trackingNumber": tracking_number,
            "status": "Label Created",
            "estimatedDeliveryDate": None, # Can be updated later
            "location": data["senderCity"],
            "statusUpdates": ["Shipping label created."]
        }

        response_data = {
            "labelImage": new_label["labelImage"],
            "shippingCost": new_label["shippingCost"],
            "trackingNumber": new_label["trackingNumber"]
        }
        return jsonify(response_data), 200

    except ValueError:
        return make_error("INVALID_DATA_TYPE", "Invalid data type for packageWeight.", status_code=400)
    except Exception as e:
        app.logger.error(f"Error generating label: {e}")
        return make_error("INTERNAL_SERVER_ERROR", "An unexpected error occurred.", status_code=500)


@app.route('/pickups', methods=['POST'])
def schedule_pickup():
    """
    Schedules a shipping pickup.
    """
    if not request.is_json:
        return make_error("INVALID_REQUEST_FORMAT", "Request body must be JSON.", status_code=400)

    data = request.get_json()
    required_fields = [
        "contactName", "contactPhone", "pickupAddress", "pickupCity",
        "pickupDate", "pickupState", "pickupTime", "pickupZip"
    ]

    for field in required_fields:
        if field not in data:
            return make_error("MISSING_FIELD", f"Missing required field: {field}", status_code=400)

    try:
        pickup_id = str(uuid.uuid4())
        # For the response, we'll use some placeholder data for inventory check
        # In a real scenario, this would involve checking actual inventory
        sku = data.get("sku", "DEFAULT_SKU_" + pickup_id[:8]) # Use provided SKU or generate one

        new_pickup = {
            "pickupId": pickup_id,
            "contactName": data["contactName"],
            "contactPhone": data["contactPhone"],
            "pickupAddress": data["pickupAddress"],
            "pickupCity": data["pickupCity"],
            "pickupDate": data["pickupDate"],
            "pickupState": data["pickupState"],
            "pickupTime": data["pickupTime"],
            "pickupZip": data["pickupZip"],
            # Fields for inventorycheckresponse
            "sku": sku,
            "availableQuantity": 100, # Placeholder
            "location": "Main Warehouse", # Placeholder
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
        pickups_db[pickup_id] = new_pickup

        response_data = {
            "sku": new_pickup["sku"],
            "availableQuantity": new_pickup["availableQuantity"],
            "location": new_pickup["location"],
            "timestamp": new_pickup["timestamp"]
        }
        return jsonify(response_data), 200

    except Exception as e:
        app.logger.error(f"Error scheduling pickup: {e}")
        return make_error("INTERNAL_SERVER_ERROR", "An unexpected error occurred.", status_code=500)


@app.route('/trackings/<string:trackingNumber>', methods=['GET'])
def get_tracking_info(trackingNumber):
    """
    Retrieves tracking information for a given tracking number.
    """
    if not trackingNumber: # Should be caught by Flask routing, but good practice
        return make_error("INVALID_INPUT", "Tracking number cannot be empty.", status_code=400)

    tracking_info = tracking_db.get(trackingNumber)

    if tracking_info:
        # Ensure all required fields for TrackingInfo are present
        response_data = {
            "trackingNumber": tracking_info.get("trackingNumber"),
            "status": tracking_info.get("status"),
            "estimatedDeliveryDate": tracking_info.get("estimatedDeliveryDate"),
            "location": tracking_info.get("location"),
            "statusUpdates": tracking_info.get("statusUpdates", [])
        }
        # Filter out None values for optional fields to match schema more closely
        response_data = {k: v for k, v in response_data.items() if v is not None or k in ["trackingNumber", "status"]}

        return jsonify(response_data), 200
    else:
        return make_error("NOT_FOUND", f"Tracking number '{trackingNumber}' not found.", status_code=404)

if __name__ == '__main__':
    app.run(debug=True, port=5001)