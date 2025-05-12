import uuid
from datetime import datetime, timezone, date
from flask import Flask, request, jsonify, make_response
from functools import wraps

app = Flask(__name__)

ORDER_STATUSES = [
    "Pending", "AwaitingPayment", "AwaitingFulfillment", "AwaitingShipment",
    "Shipped", "PartiallyShipped", "Delivered", "Cancelled", "Returned", "Disputed"
]
PAYMENT_STATUSES = ["Pending", "Authorized", "Paid", "Failed", "Refunded"]


# In-memory store for orders.
# This list will hold all created orders and can be pre-populated.
# Data will be lost if the server restarts.
orders_db = [
    {
        "orderId": "ORD-SAMPLE-001", # Using a predictable ID for the sample
        "orderDate": datetime.now(timezone.utc).isoformat(),
        "lastUpdateDate": datetime.now(timezone.utc).isoformat(),
        "customerDetails": {
            "customerId": "CUST-001",
            "email": "john.doe@example.com",
            "firstName": "John",
            "lastName": "Doe",
            "phone": "555-1234"
        },
        "itemsOrdered": [
            {
                "itemId": "ITEM-A100",
                "productName": "Wireless Mouse",
                "quantity": 1,
                "price": 25.99
            },
            {
                "itemId": "ITEM-B205",
                "productName": "Keyboard",
                "quantity": 1,
                "price": 75.00
            }
        ],
        "shippingAddress": {
            "street": "123 Main St",
            "city": "Anytown",
            "state": "CA",
            "zip": "90210",
            "country": "USA"
        },
        "billingAddress": { # Assuming same as shipping for this example
            "street": "123 Main St",
            "city": "Anytown",
            "state": "CA",
            "zip": "90210",
            "country": "USA"
        },
        "paymentDetails": {
            "paymentMethod": "Credit Card",
            "transactionId": "txn_sample_123abc",
            "paymentStatus": "Authorized"
        },
        "notes": "This is a pre-populated sample order.",
        "orderTotal": 100.99, # Sum of (25.99*1) + (75.00*1)
        "orderStatus": "Pending"
    }
]

def calculate_order_total(items_ordered):
    """Calculates the total amount for an order based on its items."""
    total = 0.0
    if items_ordered:
        for item in items_ordered:
            total += item.get("quantity", 0) * item.get("price", 0.0)
    return round(total, 2)

def _validate_address_details(address_data, address_field_name, errors, is_update=False):
    """Helper to validate address objects."""
    if not isinstance(address_data, dict):
        errors.append({"code": "INVALID_TYPE", "message": f"{address_field_name} must be an object.", "field": address_field_name})
        return
    
    required_address_fields = ["street", "city", "state", "zip", "country"]
    for field in required_address_fields:
        if field not in address_data and not is_update: # Only enforce if not an update or if field is explicitly present
            errors.append({"code": "MISSING_FIELD", "message": f"Missing required field in {address_field_name}: {field}", "field": f"{address_field_name}.{field}"})
        elif field in address_data and not isinstance(address_data[field], str):
             errors.append({"code": "INVALID_TYPE", "message": f"Field {address_field_name}.{field} must be a string.", "field": f"{address_field_name}.{field}"})


def _validate_payment_details(payment_data, errors, is_update=False):
    """Helper to validate paymentDetails object."""
    if not isinstance(payment_data, dict):
        errors.append({"code": "INVALID_TYPE", "message": "paymentDetails must be an object.", "field": "paymentDetails"})
        return

    if "paymentMethod" not in payment_data and not is_update:
        errors.append({"code": "MISSING_FIELD", "message": "Missing required field in paymentDetails: paymentMethod", "field": "paymentDetails.paymentMethod"})
    elif "paymentMethod" in payment_data and not isinstance(payment_data.get("paymentMethod"), str):
        errors.append({"code": "INVALID_TYPE", "message": "Field paymentDetails.paymentMethod must be a string.", "field": "paymentDetails.paymentMethod"})

    if "transactionId" in payment_data and not isinstance(payment_data.get("transactionId"), str):
        errors.append({"code": "INVALID_TYPE", "message": "Field paymentDetails.transactionId must be a string.", "field": "paymentDetails.transactionId"})

    if "paymentStatus" in payment_data:
        status = payment_data.get("paymentStatus")
        if not isinstance(status, str):
            errors.append({"code": "INVALID_TYPE", "message": "Field paymentDetails.paymentStatus must be a string.", "field": "paymentDetails.paymentStatus"})
        elif status not in PAYMENT_STATUSES:
            errors.append({"code": "INVALID_VALUE", "message": f"Field paymentDetails.paymentStatus must be one of {PAYMENT_STATUSES}.", "field": "paymentDetails.paymentStatus"})


def validate_order_data(data, is_update=False):
    """
    Validates incoming order data.
    For creation (is_update=False), based on OrderInput schema.
    For update (is_update=True), based on OrderUpdate schema (fields are optional).
    Returns a list of error objects if validation fails, otherwise an empty list.
    """
    errors = []

    if not isinstance(data, dict):
        errors.append({"code": "INVALID_PAYLOAD", "message": "Request payload must be a JSON object.", "field": None})
        return errors

    # For creation, check top-level required fields from OrderInput
    if not is_update:
        required_order_input_fields = ["customerDetails", "itemsOrdered", "shippingAddress", "billingAddress"]
        for field in required_order_input_fields:
            if field not in data:
                errors.append({"code": "MISSING_FIELD", "message": f"Missing required field: {field}", "field": field})

    # Validate CustomerDetails
    if "customerDetails" in data:
        customer_details = data.get("customerDetails")
        if not isinstance(customer_details, dict):
            errors.append({"code": "INVALID_TYPE", "message": "customerDetails must be an object.", "field": "customerDetails"})
        else:
            required_customer_fields = ["customerId", "email", "firstName", "lastName", "phone"]
            for field in required_customer_fields:
                if field not in customer_details and not is_update:
                    errors.append({"code": "MISSING_FIELD", "message": f"Missing required field in customerDetails: {field}", "field": f"customerDetails.{field}"})
                elif field in customer_details and not isinstance(customer_details.get(field), str):
                    errors.append({"code": "INVALID_TYPE", "message": f"Field customerDetails.{field} must be a string.", "field": f"customerDetails.{field}"})

    # Validate ItemsOrdered
    if "itemsOrdered" in data:
        items_ordered_data = data.get("itemsOrdered")
        # minItems: 1 is required for both OrderInput and if itemsOrdered is present in OrderUpdate
        if not isinstance(items_ordered_data, list) or not items_ordered_data: 
            errors.append({"code": "INVALID_FIELD", "message": "itemsOrdered must be a non-empty list.", "field": "itemsOrdered"})
        else:
            for i, item in enumerate(items_ordered_data):
                if not isinstance(item, dict):
                    errors.append({"code": "INVALID_TYPE", "message": f"Each item in itemsOrdered must be an object.", "field": f"itemsOrdered[{i}]"})
                    continue 
                required_item_fields = ["itemId", "productName", "quantity", "price"]
                for field in required_item_fields:
                    if field not in item:
                        errors.append({"code": "MISSING_FIELD", "message": f"Missing required field in itemsOrdered[{i}]: {field}", "field": f"itemsOrdered[{i}].{field}"})
                        continue # Avoid further checks on this item if core fields missing
                    # Type checks for item fields
                    if field in ["itemId", "productName"] and not isinstance(item.get(field), str):
                        errors.append({"code": "INVALID_TYPE", "message": f"Field itemsOrdered[{i}].{field} must be a string.", "field": f"itemsOrdered[{i}].{field}"})
                if "quantity" in item and not isinstance(item.get("quantity"), int):
                     errors.append({"code": "INVALID_TYPE", "message": f"Field itemsOrdered[{i}].quantity must be an integer.", "field": f"itemsOrdered[{i}].quantity"})
                if "price" in item and not isinstance(item.get("price"), (int, float)):
                     errors.append({"code": "INVALID_TYPE", "message": f"Field itemsOrdered[{i}].price must be a number.", "field": f"itemsOrdered[{i}].price"})

    # Validate ShippingAddress
    if "shippingAddress" in data:
        _validate_address_details(data.get("shippingAddress"), "shippingAddress", errors, is_update)

    # Validate BillingAddress
    if "billingAddress" in data:
        _validate_address_details(data.get("billingAddress"), "billingAddress", errors, is_update)

    # Validate PaymentDetails (optional for OrderInput, optional fields for OrderUpdate)
    if "paymentDetails" in data:
        _validate_payment_details(data.get("paymentDetails"), errors, is_update)

    # Validate notes (optional string)
    if "notes" in data and data.get("notes") is not None and not isinstance(data.get("notes"), str):
        errors.append({"code": "INVALID_TYPE", "message": "Field notes must be a string or null.", "field": "notes"})

    # Validate orderStatus (only for OrderUpdate)
    if is_update and "orderStatus" in data:
        status = data.get("orderStatus")
        if not isinstance(status, str):
            errors.append({"code": "INVALID_TYPE", "message": "Field orderStatus must be a string.", "field": "orderStatus"})
        elif status not in ORDER_STATUSES:
            errors.append({"code": "INVALID_VALUE", "message": f"Field orderStatus must be one of {ORDER_STATUSES}.", "field": "orderStatus"})

    return errors

def require_json_content_type(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        content_type = request.headers.get('Content-Type')
        if not content_type or 'application/json' not in content_type.lower():
            return jsonify([{"code": "INVALID_CONTENT_TYPE", "message": "Content-Type must be application/json."}]), 400
        return f(*args, **kwargs)
    return decorated_function

def find_order_by_id(order_id):
    """Finds an order in the mock DB by its ID."""
    return next((order for order in orders_db if order["orderId"] == order_id), None)

@app.route('/orders', methods=['POST'])
@require_json_content_type
def create_order():
    """
    Submits a new sales order to the OMS/ERP.
    """
    try:
        data = request.get_json(silent=True) # silent=True to avoid raising Werkzeug BadRequest
        if data is None: # Handles cases where JSON is malformed or body is empty
            return jsonify([{"code": "INVALID_REQUEST", "message": "Request body must be valid JSON and not empty."}]), 400

        validation_errors = validate_order_data(data)
        if validation_errors:
            return jsonify(validation_errors), 400

        # Create the new order object based on input, then add/overwrite system-generated fields
        new_order = {}
        new_order.update(data) # Copy validated input data

        # System-generated fields
        new_order['orderId'] = str(uuid.uuid4())
        now_iso = datetime.now(timezone.utc).isoformat()
        new_order['orderDate'] = now_iso
        new_order['lastUpdateDate'] = now_iso
        new_order['orderStatus'] = "Pending" # Default status for new orders
        new_order['orderTotal'] = calculate_order_total(data.get("itemsOrdered", []))

        # Ensure optional fields from OrderInput are present if provided, or set to None
        new_order.setdefault('paymentDetails', None)
        new_order.setdefault('notes', None)
        # Store the order in our in-memory list
        orders_db.append(new_order)

        # Return the created order with a 201 status
        return jsonify(new_order), 201

    except Exception as e:
        # Log the exception for server-side debugging
        app.logger.error(f"An unexpected error occurred: {e}", exc_info=True)
        return jsonify({"code": "INTERNAL_ERROR", "message": "An unexpected error occurred."}), 500

@app.route('/orders', methods=['GET'])
def list_orders():
    """Retrieves a list of orders, with support for pagination and filtering."""
    try:
        # Filtering parameters
        customer_id_filter = request.args.get('customerId')
        status_filter = request.args.get('status')
        date_from_str = request.args.get('dateFrom')
        date_to_str = request.args.get('dateTo')

        # Pagination parameters
        try:
            limit = int(request.args.get('limit', 20))
            offset = int(request.args.get('offset', 0))
        except ValueError:
            return jsonify([{"code": "INVALID_PARAMETER", "message": "Limit and offset must be integers."}]), 400

        if not (1 <= limit <= 100):
            return jsonify([{"code": "INVALID_PARAMETER", "message": "Limit must be between 1 and 100."}]), 400
        if offset < 0:
            return jsonify([{"code": "INVALID_PARAMETER", "message": "Offset must be non-negative."}]), 400

        filtered_orders = orders_db

        if customer_id_filter:
            filtered_orders = [o for o in filtered_orders if o['customerDetails'].get('customerId') == customer_id_filter]
        if status_filter:
            if status_filter not in ORDER_STATUSES:
                 return jsonify([{"code": "INVALID_PARAMETER", "message": f"Invalid status value. Allowed: {ORDER_STATUSES}"}]), 400
            filtered_orders = [o for o in filtered_orders if o.get('orderStatus') == status_filter]

        date_from_filter = None
        if date_from_str:
            try:
                date_from_filter = datetime.strptime(date_from_str, '%Y-%m-%d').date()
            except ValueError:
                return jsonify([{"code": "INVALID_PARAMETER", "message": "Invalid dateFrom format. Use YYYY-MM-DD."}]), 400

        date_to_filter = None
        if date_to_str:
            try:
                date_to_filter = datetime.strptime(date_to_str, '%Y-%m-%d').date()
            except ValueError:
                return jsonify([{"code": "INVALID_PARAMETER", "message": "Invalid dateTo format. Use YYYY-MM-DD."}]), 400

        if date_from_filter or date_to_filter:
            def check_date(order):
                order_date_obj = datetime.fromisoformat(order['orderDate']).date()
                if date_from_filter and order_date_obj < date_from_filter:
                    return False
                if date_to_filter and order_date_obj > date_to_filter:
                    return False
                return True
            filtered_orders = [o for o in filtered_orders if check_date(o)]

        total_count = len(filtered_orders)
        paginated_orders = filtered_orders[offset : offset + limit]

        response = make_response(jsonify(paginated_orders), 200)
        response.headers['X-Total-Count'] = total_count
        return response

    except Exception as e:
        app.logger.error(f"An unexpected error occurred while listing orders: {e}", exc_info=True)
        return jsonify({"code": "INTERNAL_ERROR", "message": "An unexpected error occurred."}), 500

@app.route('/orders/<string:orderId>', methods=['GET'])
def get_order(orderId):
    """Fetches the details of an order by its unique ID."""
    order = find_order_by_id(orderId)
    if order:
        return jsonify(order), 200
    else:
        return jsonify({"code": "NOT_FOUND", "message": f"Order with ID {orderId} not found."}), 404

@app.route('/orders/<string:orderId>', methods=['PUT'])
@require_json_content_type
def update_order(orderId):
    """Modifies the details of an existing order."""
    order = find_order_by_id(orderId)
    if not order:
        return jsonify({"code": "NOT_FOUND", "message": f"Order with ID {orderId} not found."}), 404

    # For a stub, we might allow updates on 'Pending' or 'AwaitingPayment' orders
    if order.get("orderStatus") in ["Shipped", "Delivered", "Cancelled"]:
        return jsonify({"code": "CONFLICT_ERROR", "message": f"Order {orderId} cannot be updated in its current state: {order.get('orderStatus')}."}), 409

    data = request.get_json(silent=True)
    if data is None:
        return jsonify([{"code": "INVALID_REQUEST", "message": "Request body must be valid JSON and not empty."}]), 400

    validation_errors = validate_order_data(data, is_update=True)
    if validation_errors:
        return jsonify(validation_errors), 400

    # Update fields present in the request data
    for key, value in data.items():
        if key in order or key in ["notes", "paymentDetails"]: # Allow adding optional fields
            if key == "itemsOrdered" and value is not None: # Ensure itemsOrdered is not set to None
                order[key] = value
                order["orderTotal"] = calculate_order_total(value)
            elif key != "orderId" and key != "orderDate" and key != "orderTotal": # Protect read-only/system fields
                 order[key] = value

    order['lastUpdateDate'] = datetime.now(timezone.utc).isoformat()

    return jsonify(order), 200

@app.route('/orders/<string:orderId>', methods=['DELETE'])
def cancel_order(orderId):
    """Marks an order as cancelled if it's in a state that allows cancellation."""
    order = find_order_by_id(orderId)
    if not order:
        return jsonify({"code": "NOT_FOUND", "message": f"Order with ID {orderId} not found."}), 404

    # Example conflict: Cannot cancel if already shipped, delivered, or cancelled
    if order.get("orderStatus") in ["Shipped", "Delivered", "Cancelled"]:
        return jsonify({
            "code": "CONFLICT_ERROR",
            "message": f"Order {orderId} cannot be cancelled in its current state: {order.get('orderStatus')}."
        }), 409

    order['orderStatus'] = "Cancelled"
    order['lastUpdateDate'] = datetime.now(timezone.utc).isoformat()
    
    # For DELETE, a 204 No Content response is typical, with no body.
    return '', 204


if __name__ == '__main__':
    # Run the Flask app
    # For development/stubbing purposes, debug=True is fine.
    # In a production scenario, use a proper WSGI server like Gunicorn or uWSGI.
    app.run(host='0.0.0.0', port=5001, debug=True)