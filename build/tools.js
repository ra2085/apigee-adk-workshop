import { z } from "zod";
// =========================
// Parameter Schemas
// =========================
const listProductsParameters = z.object({}); // No parameters
const listProductSpecsParameters = z.object({
    productName: z.string().min(1, "Product name cannot be empty."),
});
const getSpecContentParameters = z.object({
    productName: z.string().min(1, "Product name cannot be empty."),
    specPath: z.string().min(1, "Specification path cannot be empty."),
});
const getAllProductSpecsContentParameters = z.object({}); // No parameters
// =========================
// Tools Definition
// =========================
/**
 * Returns an array of tools representing the available operations in McpApi.
 */
export const tools = () => [
    // =========================
    // Product & Spec Tools
    // =========================
    {
        method: "listProducts",
        name: "List Products",
        description: "Retrieves a list of available API Product names from the MCP.",
        parameters: listProductsParameters,
        category: "products"
    },
    {
        method: "listProductSpecs",
        name: "List Product Specifications",
        description: "Retrieves the list of API specifications (and associated metadata) linked to a specific API Product.",
        parameters: listProductSpecsParameters,
        category: "specs"
    },
    {
        method: "getSpecContent",
        name: "Get Specification Content",
        description: "Retrieves the raw content (e.g., YAML or JSON) of a specific API specification file identified by its product name and path.",
        parameters: getSpecContentParameters,
        category: "content"
    },
    {
        method: "getAllProductSpecsContent",
        name: "Get All Product Specifications Content",
        description: "Retrieves all products, lists their associated specs, and fetches the content for every spec, utilizing an in-memory cache.",
        parameters: getAllProductSpecsContentParameters,
        category: "content"
    }
];
