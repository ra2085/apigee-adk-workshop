import axios from 'axios';
/**
 * Executes an API call defined by an OpenApiTool.
 *
 * @param input - The necessary information to execute the tool.
 * @returns The response data from the target API.
 * @throws Error if the tool is not found, required details are missing, or the API call fails.
 */
export const executeOpenApiTool = async (input) => {
    const { method, parameters, getAuthenticationHeaders, executionDetails } = input;
    // 1. Handle direct return value tools first
    if (executionDetails.isDirectReturnValue) {
        console.log(`[API Executor] Tool '${method}' is a direct return value tool. Returning predefined data.`);
        return {
            content: [
                {
                    type: "text",
                    text: executionDetails.directReturnValue,
                },
            ],
        };
    }
    // 2. Retrieve execution details
    const { targetServer, httpMethod, apiPath, openapiParameters = [], openapiRequestBody } = executionDetails;
    // Validate required fields for an actual API call
    if (!targetServer) {
        throw new Error(`Target server URL is missing for tool '${method}'.`);
    }
    if (!httpMethod) {
        throw new Error(`HTTP method is missing for tool '${method}'. This should be set for non-direct return tools.`);
    }
    if (!apiPath) {
        throw new Error(`API path is missing for tool '${method}'. This should be set for non-direct return tools.`);
    }
    // 3. Construct the HTTP Request
    let url = `${targetServer}${apiPath}`;
    const queryParams = {};
    const headers = {
        'Content-Type': 'application/json', // Default, might be overridden by spec
        'Accept': 'application/json', // Default, might be overridden by spec
    };
    let requestBody = undefined;
    // --- Process parameters based on OpenAPI definition ---
    // Separate parameters based on their 'in' location (path, query, header)
    openapiParameters.forEach((paramOrRef) => {
        // Basic handling: assumes parameters are not $ref objects here,
        // as generation step filters them out or should resolve them.
        // A production system might need more robust $ref handling here too.
        if ('$ref' in paramOrRef) {
            console.warn(`Skipping unresolved parameter reference: ${paramOrRef.$ref} during execution of ${method}`);
            return;
        }
        const param = paramOrRef;
        const paramName = param.name;
        const paramValue = parameters[paramName];
        if (paramValue === undefined && param.required) {
            console.warn(`Required parameter '${paramName}' is missing for tool '${method}'. API might reject.`);
            // Depending on strictness, you might throw an error here
            // throw new Error(`Required parameter '${paramName}' is missing for tool '${method}'.`);
        }
        if (paramValue !== undefined) {
            switch (param.in) {
                case 'path':
                    // Replace path placeholders like {userId}
                    url = url.replace(`{${paramName}}`, encodeURIComponent(String(paramValue)));
                    break;
                case 'query':
                    queryParams[paramName] = paramValue;
                    break;
                case 'header':
                    headers[paramName] = String(paramValue);
                    break;
                // 'cookie' parameters are less common for server-to-server calls and ignored here
            }
        }
    });
    // --- Process request body ---
    if (parameters.body) {
        requestBody = parameters.body;
        // Potentially check openapiRequestBody for content type if needed
        // const contentType = Object.keys(openapiRequestBody?.content ?? {})[0] || 'application/json';
        // headers['Content-Type'] = contentType;
    }
    else if (openapiRequestBody && openapiRequestBody.required) {
        console.warn(`Required request body is missing for tool '${method}'. API might reject.`);
        // Depending on strictness, you might throw an error here
        // throw new Error(`Required request body is missing for tool '${method}'.`);
    }
    // 4. Apply Authentication
    const authHeaders = await getAuthenticationHeaders();
    Object.assign(headers, authHeaders); // Merge auth headers
    // 5. Execute the Request using axios
    const config = {
        method: httpMethod, // Cast to Axios's Method type
        url: url,
        headers: headers,
        params: queryParams,
        data: requestBody,
    };
    console.log(`[API Executor] Executing tool '${method}': ${config.method} ${config.url}`);
    // console.debug("[API Executor] Request Config:", config); // Optional: Log full config for debugging
    try {
        const response = await axios(config);
        // 6. Return the response data
        console.log(`[API Executor] Tool '${method}' executed successfully.`);
        return {
            content: [
                {
                    type: "text",
                    //Stringify the result for text output
                    text: JSON.stringify(response.data)
                }
            ]
        };
    }
    catch (error) {
        console.error(`[API Executor] Error executing tool '${method}':`, error.message);
        if (axios.isAxiosError(error) && error.response) {
            console.error(`[API Executor] API Response Status: ${error.response.status}`);
            console.error(`[API Executor] API Response Data:`, error.response.data);
            return {
                content: [
                    {
                        type: "text",
                        //Stringify the result for text output
                        text: JSON.stringify(error.response.data)
                    }
                ],
                isError: true
            };
        }
        // Re-throw original error if it's not an Axios error or has no response
        throw error;
    }
};
