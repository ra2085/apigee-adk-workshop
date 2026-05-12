import os
from google.adk.agents import Agent
from google.adk.models.apigee_llm import ApigeeLlm
from google.adk.tools.mcp_tool.mcp_toolset import McpToolset, StreamableHTTPConnectionParams
from google.adk.auth.credential_manager import CredentialManager
from google.adk.integrations.agent_identity import GcpAuthProvider, GcpAuthProviderScheme
from google.adk.auth.auth_tool import AuthConfig
from google.adk.tools.authenticated_function_tool import AuthenticatedFunctionTool

LOCATION = os.environ.get('GOOGLE_CLOUD_LOCATION')
AUTH_CONNECTOR = os.environ.get("AUTH_CONNECTOR")
APIGEE_HOST = os.environ.get("APIGEE_HOST")
AI_GATEWAY_PATH = "/ai-gateway/v1"

CredentialManager.register_auth_provider(GcpAuthProvider())

auth_scheme = GcpAuthProviderScheme(
    name=f"projects/PROJECT_PLACEHOLDER/locations/us-central1/connectors/apigee"
)

system_instruction = (
    "You are a strict but helpful retail operations coordinator. "
    "Your goal is to help regional retail managers verify display compliance, analyze performance, and coordinate marketing materials.\n"
    "You must ONLY perform tasks that can be fulfilled by using the available tools:\n"
    "- getPlanogramV1StatusStoreId: Check compliance status for a store. Requires 'store_id'.\n"
    "- getAnalyticsV1FootTrafficStoreId: Get hourly foot traffic data. Requires 'store_id'.\n"
    "- postOrdersV1Signage: Submit an order for signage kits.\n"
    "Do not assume or offer capabilities beyond these tools.\n\n"
)

model = ApigeeLlm(
    model="apigee/gemini-3.1-flash-lite-preview",
    proxy_url=f"https://{APIGEE_HOST}{AI_GATEWAY_PATH}",
)

mcp_tools = McpToolset(
    connection_params=StreamableHTTPConnectionParams(
        url=f"https://{APIGEE_HOST}/mcp",
    ),
    auth_scheme=auth_scheme,
)

root_agent = Agent(
    model=model,
    name="merchandising_assistant_agent",
    instruction=system_instruction,
    tools=[mcp_tools]
)

if __name__ == "__main__":
    print(f"Agent created: {root_agent.name}")
