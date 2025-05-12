from dataclasses import dataclass, asdict
from typing import List, Optional, Dict, Any, Union
from flask import Flask, jsonify, request, abort

# Schemas from components/schemas

@dataclass
class Error:
    """Schema for error responses."""
    code: str
    message: str
    details: Optional[str] = None

@dataclass
class LeadTime:
    """The estimated lead time for the product."""
    days: int
    description: str

@dataclass
class StockLevel:
    """
    Represents the stock level of a product, including available quantity,
    incoming quantity, and backorder availability.
    """
    available: int
    incoming: int
    backorderable: bool

@dataclass
class ItemOrdered:
    """Details of an item included in the order.
    (Corresponds to OpenAPI schema: itemordered)
    """
    itemId: str
    productName: str
    quantity: int
    price: float

@dataclass
class ShippingAddress:
    """Address to which the order will be shipped.
    (Corresponds to OpenAPI schema: shippingaddress)
    """
    street: str
    city: str
    state: str
    zip_code: str  # OpenAPI 'zip' renamed to 'zip_code' to avoid conflict
    country: str

# Inline Schemas used in paths (derived and named for clarity)

@dataclass
class ProductDetail:
    """Detailed information for a specific product.
    (Derived from GET /products/{productId} response schema)
    """
    productId: str  # Interpreted: OpenAPI schema for this field was 'itemordered', corrected to 'str'
    name: str
    description: str
    price: float  # Interpreted: OpenAPI schema for this field was 'itemordered', corrected to 'float'
    stockLevel: StockLevel
    leadTime: LeadTime
    p2OFlag: bool # Interpreted: OpenAPI schema for this field was 'shippingaddress', corrected to 'bool'
    additionalProperties: Optional[Dict[str, Any]] = None


@dataclass
class ProductUpdateData:
    """Product details to update.
    (Derived from PUT /products/{productId} request body schema)
    """
    name: str
    description: str
    price: float  # Interpreted: OpenAPI schema for this field was 'itemordered', corrected to 'float'
    stockLevel: StockLevel
    leadTime: LeadTime
    p2OFlag: bool # Interpreted: OpenAPI schema for this field was 'shippingaddress', corrected to 'bool'
    additionalProperties: Optional[Dict[str, Any]] = None


@dataclass
class ProductAvailability:
    """Availability information for a specific product.
    (Derived from GET /products/{productId}/availability response schema)
    """
    stockLevel: StockLevel
    leadTime: LeadTime
    p2OFlag: bool # Interpreted: OpenAPI schema for this field was 'shippingaddress', corrected to 'bool'


# Helper function to create default product data
def _create_default_product_data() -> Dict[str, ProductDetail]:
    """Creates and returns a dictionary of default product details."""
    sl1 = StockLevel(available=10, incoming=5, backorderable=True)
    lt1 = LeadTime(days=2, description="Ships in 2 days")
    pd1 = ProductDetail(
        productId="P001", name="Laptop Pro", description="High-end laptop for professionals.",
        price=1200.00, stockLevel=sl1, leadTime=lt1, p2OFlag=False,
        additionalProperties={"color": "red", "material": "metal"}
    )

    sl2 = StockLevel(available=0, incoming=10, backorderable=False)
    lt2 = LeadTime(days=7, description="Ships in 1 week (P2O)")
    pd2 = ProductDetail(
        productId="P002", name="Wireless Mouse", description="Ergonomic wireless mouse.",
        price=25.00, stockLevel=sl2, leadTime=lt2, p2OFlag=True
    )

    sl3 = StockLevel(available=100, incoming=0, backorderable=True)
    lt3 = LeadTime(days=1, description="Ships next day")
    pd3 = ProductDetail(
        productId="P003", name="Keyboard Basic", description="Standard USB keyboard.",
        price=15.00, stockLevel=sl3, leadTime=lt3, p2OFlag=False
    )
    return {"P001": pd1, "P002": pd2, "P003": pd3}

# API Endpoint Stubs

class ProductCatalogService:
    """
    Stub for the Product Catalog & Availability API.
    Enables the frontend to query product information, pricing, and crucially,
    determine if an item is typically P2O or if there's any existing
    stock/incoming stock that could fulfill it (sometimes P2O is a fallback).
    """
    _products: Dict[str, ProductDetail]

    def __init__(self, initial_products: Optional[Dict[str, ProductDetail]] = None):
        if initial_products is not None:
            self._products = initial_products
        else:
            self._products = _create_default_product_data() # Load defaults

    def get_products(
        self,
        page: Optional[int] = None,
        page_size: Optional[int] = None,
        filter_str: Optional[str] = None
    ) -> List[ItemOrdered]:
        """
        Retrieves a list of products, with optional filtering or pagination.
        Returns basic product information, price, and availability status.
        (Corresponds to GET /products)

        Args:
            page: Page number for pagination (OpenAPI name: 'page'). Minimum: 1.
            page_size: Number of products per page (OpenAPI name: 'pageSize'). Minimum: 1, Maximum: 100.
            filter_str: Filter products based on certain criteria (e.g., category, price range)
                        (OpenAPI name: 'filter').

        Returns:
            A list of products (Interpreted: OpenAPI response schema is 'itemordered',
            but description implies a list).
        
        Raises:
            NotImplementedError: This is a stub and the method is not implemented.
        """
        if page is not None and page < 1:
            raise ValueError("Page number must be >= 1")
        if page_size is not None and not (1 <= page_size <= 100):
            raise ValueError("Page size must be between 1 and 100")

        product_list = list(self._products.values())

        # Apply filtering
        if filter_str:
            filter_lower = filter_str.lower()
            product_list = [
                p for p in product_list if
                filter_lower in p.name.lower() or
                (p.description and filter_lower in p.description.lower())
            ]

        # Apply pagination
        if page is not None or page_size is not None:
            current_page = page if page is not None else 1
            current_page_size = page_size if page_size is not None else 20 # Default page size

            start_index = (current_page - 1) * current_page_size
            end_index = start_index + current_page_size
            product_list = product_list[start_index:end_index]

        # Convert to ItemOrdered
        result_items = [
            ItemOrdered(
                itemId=p.productId,
                productName=p.name,
                quantity=p.stockLevel.available, # Using available stock for quantity
                price=p.price
            ) for p in product_list
        ]
        return result_items
        
    def delete_product(self, product_id: str) -> None:
        """
        Deletes a product from the catalog based on its ID.
        (Corresponds to DELETE /products/{productId}, operationId: deleteProduct)

        Args:
            product_id: Unique identifier for the product.
        
        Raises:
            NotImplementedError: This is a stub and the method is not implemented.
        """
        if product_id in self._products:
            del self._products[product_id]
        # No explicit return for 204 No Content

    def get_product_by_id(self, product_id: str) -> Optional[ProductDetail]:
        """
        Retrieves detailed information for a specific product, including product
        details, price, stock levels, lead times, and the P2O flag.
        (Corresponds to GET /products/{productId})

        Args:
            product_id: Unique identifier for the product.

        Returns:
            Detailed information for the specified product, or None if not found.
        
        Raises:
            NotImplementedError: This is a stub and the method is not implemented.
        """
        return self._products.get(product_id)

    def update_product(self, product_id: str, product_data: ProductUpdateData) -> Optional[ItemOrdered]:
        """
        Updates the details of a specific product.
        (Corresponds to PUT /products/{productId}, operationId: updateProduct)

        Args:
            product_id: Unique identifier for the product.
            product_data: Product details to update.

        Returns:
            The updated product information (as ItemOrdered), or None if update failed.
        
        Raises:
            NotImplementedError: This is a stub and the method is not implemented.
        """
        product_to_update = self._products.get(product_id)
        if not product_to_update:
            return None

        product_to_update.name = product_data.name
        product_to_update.description = product_data.description
        product_to_update.price = product_data.price
        product_to_update.stockLevel = product_data.stockLevel
        product_to_update.leadTime = product_data.leadTime
        product_to_update.p2OFlag = product_data.p2OFlag
        product_to_update.additionalProperties = product_data.additionalProperties
        
        return ItemOrdered(
            itemId=product_to_update.productId,
            productName=product_to_update.name,
            quantity=product_to_update.stockLevel.available,
            price=product_to_update.price
        )


    def get_product_availability(self, product_id: str) -> Optional[ProductAvailability]:
        """
        Checks the availability of a specific product.
        (Corresponds to GET /products/{productId}/availability)

        Args:
            product_id: Unique identifier for the product.

        Returns:
            Availability information for the product, or None if not found.
        
        Raises:
            NotImplementedError: This is a stub and the method is not implemented.
        """
        product = self._products.get(product_id)
        if not product:
            return None
        
        return ProductAvailability(
            stockLevel=product.stockLevel,
            leadTime=product.leadTime,
            p2OFlag=product.p2OFlag
        )


app = Flask(__name__)

# Initialize service once. It will now use the default data defined
# in _create_default_product_data() via its constructor.
service = ProductCatalogService()

@app.route('/products', methods=['GET'])
def get_products_route():
    page = request.args.get('page', type=int)
    page_size = request.args.get('pageSize', type=int) # OpenAPI 'pageSize'
    filter_str = request.args.get('filter')

    try:
        products = service.get_products(page=page, page_size=page_size, filter_str=filter_str)
        return jsonify([asdict(p) for p in products])
    except ValueError as e:
        abort(400, description=str(e))

@app.route('/products/<string:product_id>', methods=['DELETE'])
def delete_product_route(product_id: str):
    product = service.get_product_by_id(product_id) # Check if exists for 404
    if not product:
        abort(404, description=f"Product with ID '{product_id}' not found.")
    service.delete_product(product_id)
    return '', 204 # No Content

@app.route('/products/<string:product_id>', methods=['GET'])
def get_product_by_id_route(product_id: str):
    product = service.get_product_by_id(product_id)
    if product:
        return jsonify(asdict(product))
    else:
        abort(404, description=f"Product with ID '{product_id}' not found.")

@app.route('/products/<string:product_id>', methods=['PUT'])
def update_product_route(product_id: str):
    if not request.is_json:
        abort(400, description="Request body must be JSON.")
    
    data = request.get_json()
    if not data:
        abort(400, description="Request body is empty or invalid JSON.")

    try:
        # Reconstruct nested dataclasses from dict
        stock_level_data = data.get('stockLevel', {})
        lead_time_data = data.get('leadTime', {})

        product_update_data = ProductUpdateData(
            name=data['name'],
            description=data['description'],
            price=data['price'],
            stockLevel=StockLevel(**stock_level_data),
            leadTime=LeadTime(**lead_time_data),
            p2OFlag=data['p2OFlag'],
            additionalProperties=data.get('additionalProperties')
        )
    except KeyError as e:
        abort(400, description=f"Missing required field: {e}")
    except TypeError as e: # Handles issues with **unpacking if fields are missing in nested dicts
        abort(400, description=f"Invalid data structure for stockLevel or leadTime: {e}")

    updated_item = service.update_product(product_id, product_update_data)
    if updated_item:
        return jsonify(asdict(updated_item))
    else:
        abort(404, description=f"Product with ID '{product_id}' not found for update.")

@app.route('/products/<string:product_id>/availability', methods=['GET'])
def get_product_availability_route(product_id: str):
    availability = service.get_product_availability(product_id)
    if availability:
        return jsonify(asdict(availability))
    else:
        abort(404, description=f"Product with ID '{product_id}' not found.")


if __name__ == "__main__":
    # The old test code is removed as Flask will run the service.
    # You can test the API using tools like curl, Postman, or by writing
    # separate integration tests using Flask's test client.
    print("Starting Flask Product Catalog Service...")
    print("Available Endpoints:")
    print("  GET    /products")
    print("  GET    /products/<product_id>")
    print("  PUT    /products/<product_id>")
    print("  DELETE /products/<product_id>")
    print("  GET    /products/<product_id>/availability")
    print("\nExample GET /products?page=1&pageSize=2&filter=Laptop")
    print("Example GET /products/P001")
    app.run(debug=True, port=5001) # Using port 5001 to avoid conflict if 5000 is in use