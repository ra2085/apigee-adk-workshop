from flask import Flask, request, jsonify
import uuid

app = Flask(__name__)

# In-memory database for orders
# Key: orderId
# Value: dictionary representing the order
orders_db = {}

# --- Helper Functions ---
def make_error(code, message, status_code, field=None):
    """Creates a JSON error response."""
    response_data = {"code": str(code), "message": message}
    if field:
        response_data["field"] = field
    return jsonify(response_data), status_code

def get_itemordered_from_order(order):
    """
    Extracts an itemordered representation from an order object.
    Returns the first item's details if available, conforming to the itemordered schema.
    """
    if order and order.get("items") and len(order["items"]) > 0:
        first_item = order["items"][0]
        # Ensure all required fields for itemordered are present in the first_item
        if all(k in first_item for k in ["itemId", "productName", "quantity", "price"]):
            return {
                "itemId": first_item.get("itemId"),
                "productName": first_item.get("productName"),
                "quantity": first_item.get("quantity"),
                "price": first_item.get("price")
            }
    return None

# --- Initial Data ---
def load_initial_data():
    """Loads initial sample orders into the in-memory database."""
    global orders_db
    order1_id = "order_init_1" # Using predictable IDs for initial data
    order2_id = "order_init_2"

    orders_db = {
        order1_id: {
            "orderId": order1_id,
            "customerName": "John Doe",
            "shippingAddress": "123 Main St, Anytown, USA",
            "billingAddress": "123 Main St, Anytown, USA",
            "items": [
                {
                    "itemId": str(uuid.uuid4()), # Unique line item ID
                    "productId": "PROD001",
                    "productName": "Laptop Pro",
                    "quantity": 1,
                    "price": 1200.00
                },
                {
                    "itemId": str(uuid.uuid4()), # Unique line item ID
                    "productId": "PROD002",
                    "productName": "Wireless Mouse",
                    "quantity": 1,
                    "price": 25.00
                }
            ],
            "orderPriority": "High",
            "shippingMethod": "Express",
            "totalAmount": 1225.00,
            "status": "Awaiting Fulfillment"
        },
        order2_id: {
            "orderId": order2_id,
            "customerName": "Jane Smith",
            "shippingAddress": "456 Oak Ave, Otherville, USA",
            "billingAddress": "456 Oak Ave, Otherville, USA",
            "items": [
                {
                    "itemId": str(uuid.uuid4()), # Unique line item ID
                    "productId": "PROD003",
                    "productName": "Coffee Maker",
                    "quantity": 1,
                    "price": 75.50
                }
            ],
            "orderPriority": "Medium",
            "shippingMethod": "Standard",
            "totalAmount": 75.50,
            "status": "Picking"
        }
    }
    print(f"Loaded initial data. Order IDs: {list(orders_db.keys())}")

# --- Routes ---

@app.route('/orders', methods=['POST'])
def create_order():
    """
    Receives new order details.
    Request body conforms to itemordered schema.
    Creates an order with a single item based on the request.
    """
    data = request.get_json()
    if not data:
        return make_error("INVALID_REQUEST_BODY", "Request body is missing or not JSON.", 400)

    required_fields = ["itemId", "productName", "quantity", "price"]
    missing_fields = [field for field in required_fields if field not in data]
    if missing_fields:
        return make_error("MISSING_FIELDS", f"Missing required fields: {', '.join(missing_fields)}", 400, missing_fields[0])

    # Type validation (basic)
    if not isinstance(data.get("quantity"), int):
        return make_error("INVALID_FIELD_TYPE", "Field 'quantity' must be an integer.", 400, "quantity")
    if not isinstance(data.get("price"), (int, float)):
        return make_error("INVALID_FIELD_TYPE", "Field 'price' must be a number.", 400, "price")


    order_id = str(uuid.uuid4())
    line_item_id = str(uuid.uuid4()) # System-generated unique ID for this line item

    new_order = {
        "orderId": order_id,
        "items": [
            {
                "itemId": line_item_id,  # This is the itemId for the line item in the order
                "productId": data["itemId"], # Request's itemId is treated as productId
                "productName": data["productName"],
                "quantity": data["quantity"],
                "price": data["price"]
            }
        ],
        "status": "Awaiting Fulfillment", # Default status
        "customerName": None,
        "shippingAddress": None,
        "billingAddress": None,
        "orderPriority": None,
        "shippingMethod": None,
        "totalAmount": data["price"] * data["quantity"]
    }
    orders_db[order_id] = new_order

    # Response is itemordered schema for the created item
    response_item = {
        "itemId": line_item_id,
        "productName": data["productName"],
        "quantity": data["quantity"],
        "price": data["price"]
    }
    return jsonify(response_item), 201

@app.route('/orders/<string:orderId>', methods=['GET'])
def get_order_details(orderId):
    """Retrieves details of a specific order by its ID."""
    order = orders_db.get(orderId)
    if not order:
        return make_error("ORDER_NOT_FOUND", "Order not found.", 404, "orderId")

    item_representation = get_itemordered_from_order(order)
    if item_representation:
        return jsonify(item_representation), 200
    else:
        # This implies an order exists but has no items or item data is malformed.
        # The spec expects itemordered, so this is an internal issue if reached.
        return make_error("NO_ITEM_REPRESENTATION", "Order found but no item data available for itemordered representation.", 500)

@app.route('/orders/<string:orderId>', methods=['PUT'])
def update_full_order(orderId):
    """
    Updates an existing order's details.
    As per spec, request body is itemordered. This will update the first item of the order.
    Note: The description "Updates ... priority or shipping address" conflicts with this schema.
    This implementation strictly follows the itemordered request body schema.
    """
    if orderId not in orders_db:
        return make_error("ORDER_NOT_FOUND", "Order not found.", 404, "orderId")

    data = request.get_json()
    if not data:
        return make_error("INVALID_REQUEST_BODY", "Request body is missing or not JSON.", 400)

    required_fields = ["itemId", "productName", "quantity", "price"]
    missing_fields = [field for field in required_fields if field not in data]
    if missing_fields:
        return make_error("MISSING_FIELDS_FOR_PUT", f"PUT request body must conform to itemordered. Missing: {', '.join(missing_fields)}", 400, missing_fields[0])

    # Type validation (basic)
    if not isinstance(data.get("quantity"), int):
        return make_error("INVALID_FIELD_TYPE", "Field 'quantity' must be an integer.", 400, "quantity")
    if not isinstance(data.get("price"), (int, float)):
        return make_error("INVALID_FIELD_TYPE", "Field 'price' must be a number.", 400, "price")

    current_order = orders_db[orderId]
    if not current_order.get("items") or not current_order["items"]:
        # If order has no items, create one based on the PUT data.
        line_item_id_for_put = str(uuid.uuid4())
        current_order["items"] = [{
            "itemId": line_item_id_for_put,
            "productId": data["itemId"], # Treat request itemId as productId
            "productName": data["productName"],
            "quantity": data["quantity"],
            "price": data["price"]
        }]
    else:
        # Update the first item's properties. Its itemId (line item ID) remains.
        # The itemId from the request (data["itemId"]) is treated as the productId.
        current_order["items"][0].update({
            "productName": data["productName"],
            "quantity": data["quantity"],
            "price": data["price"],
            "productId": data["itemId"]
        })
    
    # Recalculate totalAmount based on all items
    current_order["totalAmount"] = sum(
        item.get("price", 0) * item.get("quantity", 0) for item in current_order.get("items", [])
    )
    orders_db[orderId] = current_order
    
    item_representation = get_itemordered_from_order(current_order)
    if item_representation:
        return jsonify(item_representation), 200
    else:
        return make_error("UPDATE_FAILED_REPRESENTATION", "Order updated, but failed to create itemordered representation.", 500)

@app.route('/orders/<string:orderId>', methods=['PATCH'])
def patch_partial_order(orderId):
    """Partially updates an existing order's details."""
    if orderId not in orders_db:
        return make_error("ORDER_NOT_FOUND", "Order not found.", 404, "orderId")

    data = request.get_json()
    if not data:
        return make_error("INVALID_REQUEST_BODY", "Request body is missing or not JSON.", 400)

    order_to_update = orders_db[orderId]
    
    # Fields allowed for PATCH from spec (excluding 'items' handled separately)
    simple_patchable_fields = [
        "billingAddress", "customerName", "orderPriority",
        "shippingAddress", "shippingMethod", "totalAmount"
    ]

    for key, value in data.items():
        if key in simple_patchable_fields:
            # Basic type validation could be added here if necessary
            # e.g. if key == "totalAmount" and not isinstance(value, (int, float)):
            # return make_error("INVALID_FIELD_TYPE", f"Field '{key}' must be a number.", 400, key)
            order_to_update[key] = value
        elif key == "items":
            if not isinstance(value, list):
                return make_error("INVALID_FIELD_TYPE", "Field 'items' must be an array.", 400, "items")
            
            new_items_list = []
            for item_data in value:
                if not (isinstance(item_data, dict) and
                        "productId" in item_data and isinstance(item_data["productId"], str) and
                        "quantity" in item_data and isinstance(item_data["quantity"], int)):
                    return make_error("INVALID_ITEM_STRUCTURE", "Each item must be an object with 'productId' (string) and 'quantity' (integer).", 400, "items")
                
                new_line_item_id = str(uuid.uuid4())
                new_items_list.append({
                    "itemId": new_line_item_id,
                    "productId": item_data["productId"],
                    "quantity": item_data["quantity"],
                    "productName": f"Product {item_data['productId']}", # Dummy name, as not in patch schema
                    "price": 0.0  # Dummy price, as not in patch schema
                })
            order_to_update["items"] = new_items_list
            # If items are patched and totalAmount wasn't explicitly in patch, recalculate
            if "totalAmount" not in data:
                 order_to_update["totalAmount"] = sum(
                    item.get("price", 0) * item.get("quantity", 0) for item in order_to_update["items"]
                )
        # else:
            # Unknown fields are ignored in PATCH

    orders_db[orderId] = order_to_update
    
    item_representation = get_itemordered_from_order(order_to_update)
    if item_representation:
        return jsonify(item_representation), 200
    else:
        # This could happen if patching items results in an empty list or malformed first item.
        return make_error("PATCH_FAILED_REPRESENTATION", "Order updated, but no item data available for itemordered representation.", 500)

@app.route('/orders/<string:orderId>', methods=['DELETE'])
def delete_order_by_id(orderId):
    """Cancels an order by its ID."""
    if orderId not in orders_db:
        return make_error("ORDER_NOT_FOUND", "Order not found.", 404, "orderId")
    
    del orders_db[orderId]
    return '', 204

@app.route('/orders/<string:orderId>/status', methods=['PATCH'])
def update_order_status_by_id(orderId):
    """
    Updates the status of an order.
    Note: Spec lists requestBody schema as 'error', which is incorrect.
    Assuming request body is `{"status": "new_status"}`.
    """
    if orderId not in orders_db:
        return make_error("ORDER_NOT_FOUND", "Order not found.", 404, "orderId")

    data = request.get_json()
    if not data:
        return make_error("INVALID_REQUEST_BODY", "Request body is missing or not JSON.", 400)

    if "status" not in data or not isinstance(data["status"], str):
        return make_error("INVALID_STATUS_PAYLOAD", "Request body must contain a 'status' field as a string.", 400, "status")

    new_status = data["status"]
    # Optional: Validate new_status against a list of allowed statuses
    # e.g., allowed_statuses = ['Awaiting Fulfillment', 'Picking', 'Packed', 'Shipped', 'Delivered']
    # if new_status not in allowed_statuses:
    #    return make_error("INVALID_STATUS_VALUE", f"Invalid status. Allowed: {', '.join(allowed_statuses)}", 400, "status")

    orders_db[orderId]["status"] = new_status
    
    updated_order = orders_db[orderId]
    item_representation = get_itemordered_from_order(updated_order)
    if item_representation:
        return jsonify(item_representation), 200
    else:
        return make_error("STATUS_UPDATE_FAILED_REPRESENTATION", "Status updated, but no item data for itemordered representation.", 500)

# --- Main ---
if __name__ == '__main__':
    load_initial_data()
    # It's good practice to run on 0.0.0.0 to make it accessible externally if needed,
    # but for local dev, default (127.0.0.1) is fine.
    app.run(host='0.0.0.0', port=5001, debug=True)
