#!/bin/bash

# Upload sample data to Azure after azd provision
# This script uses azd environment variables to configure the upload

set -e

echo "======================================"
echo "Upload Sample Data (azd)"
echo "======================================"
echo ""

# Get environment values from azd safely (avoid eval with untrusted input)
if command -v azd &> /dev/null; then
    echo "Loading environment values from azd..."
    # Parse azd env values safely without eval
    while IFS='=' read -r key value; do
        case "$key" in
            AZURE_STORAGE_ACCOUNT_NAME) AZURE_STORAGE_ACCOUNT_NAME="$value" ;;
            AZURE_SEARCH_ENDPOINT) AZURE_SEARCH_ENDPOINT="$value" ;;
            AZURE_RESOURCE_GROUP) AZURE_RESOURCE_GROUP="$value" ;;
            AZURE_OPENAI_NAME) AZURE_OPENAI_NAME="$value" ;;
            AZURE_OPENAI_ENDPOINT) AZURE_OPENAI_ENDPOINT="$value" ;;
        esac
    done < <(azd env get-values 2>/dev/null | grep -E "^AZURE_" || true)
fi

# Fallback to environment variables if azd values not available
STORAGE_ACCOUNT_NAME="${AZURE_STORAGE_ACCOUNT_NAME:-$STORAGE_ACCOUNT_NAME}"
SEARCH_ENDPOINT="${AZURE_SEARCH_ENDPOINT:-$SEARCH_ENDPOINT}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$RESOURCE_GROUP}"
OPENAI_NAME="${AZURE_OPENAI_NAME:-$OPENAI_NAME}"
OPENAI_ENDPOINT="${AZURE_OPENAI_ENDPOINT:-$OPENAI_ENDPOINT}"

if [ -z "$STORAGE_ACCOUNT_NAME" ] || [ -z "$SEARCH_ENDPOINT" ] || [ -z "$RESOURCE_GROUP" ]; then
    echo "Error: Required environment variables not set."
    echo ""
    echo "This script requires either:"
    echo "  1. azd environment configured (run 'azd provision' first)"
    echo "  2. Environment variables set manually:"
    echo "     export AZURE_STORAGE_ACCOUNT_NAME='your-storage-account'"
    echo "     export AZURE_SEARCH_ENDPOINT='https://your-search.search.windows.net'"
    echo "     export AZURE_RESOURCE_GROUP='your-resource-group'"
    echo "     export AZURE_OPENAI_NAME='your-openai-account' (optional)"
    echo ""
    exit 1
fi

# Validate SEARCH_ENDPOINT format
if [[ ! "$SEARCH_ENDPOINT" =~ ^https://[a-zA-Z0-9-]+\.search\.windows\.net/?$ ]]; then
    echo "Warning: SEARCH_ENDPOINT format may be incorrect: $SEARCH_ENDPOINT"
    echo "Expected format: https://<service-name>.search.windows.net"
fi

echo "Configuration:"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Search Endpoint: $SEARCH_ENDPOINT"
echo "  Resource Group: $RESOURCE_GROUP"
[ -n "$OPENAI_NAME" ] && echo "  OpenAI Account: $OPENAI_NAME"
echo ""

# Extract search service name from endpoint with validation
SEARCH_SERVICE_NAME=$(echo "$SEARCH_ENDPOINT" | sed 's|https://||' | sed 's|\.search\.windows\.net.*||')
if [ -z "$SEARCH_SERVICE_NAME" ]; then
    echo "Error: Could not extract search service name from endpoint"
    exit 1
fi

# Get search admin key using Azure CLI
echo "[1/7] Retrieving credentials..."

az account show

SEARCH_ADMIN_KEY=$(az search admin-key show \
    --resource-group "$RESOURCE_GROUP" \
    --service-name "$SEARCH_SERVICE_NAME" \
    --query "primaryKey" -o tsv 2>&1) || {
    echo "Warning: Could not retrieve Search admin key. Using Azure CLI auth instead."
    echo "  Possible causes: insufficient permissions, incorrect resource group, or service not found."
    SEARCH_ADMIN_KEY=""
}

# Get Storage connection string for Knowledge Sources
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    -n "$STORAGE_ACCOUNT_NAME" \
    -g "$RESOURCE_GROUP" \
    --query "connectionString" -o tsv 2>/dev/null || echo "")

# Get OpenAI credentials for Knowledge Source ingestion
if [ -z "$OPENAI_NAME" ]; then
    OPENAI_NAME=$(az cognitiveservices account list -g "$RESOURCE_GROUP" --query "[?kind=='OpenAI'].name | [0]" -o tsv 2>/dev/null || echo "")
fi

OPENAI_KEY=""
if [ -n "$OPENAI_NAME" ]; then
    if [ -z "$OPENAI_ENDPOINT" ]; then
        OPENAI_ENDPOINT=$(az cognitiveservices account show \
            -n "$OPENAI_NAME" \
            -g "$RESOURCE_GROUP" \
            --query "properties.endpoint" -o tsv 2>/dev/null || echo "")
    fi
    OPENAI_KEY=$(az cognitiveservices account keys list \
        -n "$OPENAI_NAME" \
        -g "$RESOURCE_GROUP" \
        --query "key1" -o tsv 2>/dev/null || echo "")
    # Remove trailing slash from endpoint
    OPENAI_ENDPOINT="${OPENAI_ENDPOINT%/}"
fi

echo "  Credentials retrieved:"
[ -n "$STORAGE_CONNECTION_STRING" ] && echo "    ✓ Storage connection string" || echo "    ⚠ Storage connection string not available"
[ -n "$OPENAI_ENDPOINT" ] && echo "    ✓ OpenAI endpoint: $OPENAI_ENDPOINT" || echo "    ⚠ OpenAI endpoint not available"
[ -n "$OPENAI_KEY" ] && echo "    ✓ OpenAI API key" || echo "    ⚠ OpenAI API key not available"

# Download sample PDF (Microsoft Responsible AI Transparency Report)
echo ""
echo "[2/7] Downloading Microsoft Responsible AI Transparency Report..."
SAMPLE_PDF_URL="https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/msc/documents/presentations/CSR/Responsible-AI-Transparency-Report-2025-vertical.pdf"
SAMPLE_PDF_NAME="Responsible-AI-Transparency-Report-2025.pdf"

mkdir -p /tmp/sample-data
curl -L "$SAMPLE_PDF_URL" -o "/tmp/sample-data/$SAMPLE_PDF_NAME" 2>/dev/null

# Use the same container name as postprovision.sh and configure_search_objects.py
CONTAINER_NAME="${AZURE_BLOB_CONTAINER_NAME:-foundry-iq-data}"

if [ -f "/tmp/sample-data/$SAMPLE_PDF_NAME" ]; then
    echo "✓ Downloaded: $SAMPLE_PDF_NAME"
else
    echo "⚠ Failed to download PDF, continuing..."
fi

# Step 3: Upload PDF to Azure Blob Storage
echo ""
echo "[3/7] Uploading PDF to Azure Blob Storage..."

# Create container if it doesn't exist
az storage container create \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --name "$CONTAINER_NAME" \
    --auth-mode login \
    --output none 2>/dev/null || true

if [ -f "/tmp/sample-data/$SAMPLE_PDF_NAME" ]; then
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$CONTAINER_NAME" \
        --name "$SAMPLE_PDF_NAME" \
        --file "/tmp/sample-data/$SAMPLE_PDF_NAME" \
        --auth-mode login \
        --overwrite \
        --output none
    echo "✓ Uploaded to: $CONTAINER_NAME/$SAMPLE_PDF_NAME"
fi

# Step 4: Create hotels-sample index
echo ""
echo "[4/7] Creating hotels-sample index in Azure AI Search..."

HOTELS_INDEX_SCHEMA='{
  "name": "hotels-sample",
  "fields": [
    {"name": "HotelId", "type": "Edm.String", "key": true, "searchable": false},
    {"name": "HotelName", "type": "Edm.String", "searchable": true, "filterable": false, "sortable": true, "facetable": false},
    {"name": "Description", "type": "Edm.String", "searchable": true, "filterable": false, "sortable": false, "facetable": false},
    {"name": "Category", "type": "Edm.String", "searchable": true, "filterable": true, "sortable": true, "facetable": true},
    {"name": "Tags", "type": "Collection(Edm.String)", "searchable": true, "filterable": true, "sortable": false, "facetable": true},
    {"name": "Rating", "type": "Edm.Double", "searchable": false, "filterable": true, "sortable": true, "facetable": true},
    {"name": "Location", "type": "Edm.GeographyPoint", "searchable": false, "filterable": true, "sortable": true, "facetable": false},
    {"name": "Address", "type": "Edm.ComplexType", "fields": [
      {"name": "StreetAddress", "type": "Edm.String", "searchable": true},
      {"name": "City", "type": "Edm.String", "searchable": true, "filterable": true, "sortable": true, "facetable": true},
      {"name": "StateProvince", "type": "Edm.String", "searchable": true, "filterable": true, "sortable": true, "facetable": true},
      {"name": "PostalCode", "type": "Edm.String", "searchable": true, "filterable": true, "sortable": true, "facetable": true},
      {"name": "Country", "type": "Edm.String", "searchable": true, "filterable": true, "sortable": true, "facetable": true}
    ]}
  ],
  "semantic": {
    "configurations": [
      {
        "name": "hotel-semantic-config",
        "prioritizedFields": {
          "titleField": {
            "fieldName": "HotelName"
          },
          "prioritizedContentFields": [
            {"fieldName": "Description"}
          ],
          "prioritizedKeywordsFields": [
            {"fieldName": "Tags"}
          ]
        }
      }
    ]
  }
}'

# Get bearer token for Azure Search
SEARCH_TOKEN=$(az account get-access-token --resource "https://search.azure.com" --query "accessToken" -o tsv 2>/dev/null || echo "")

if [ -n "$SEARCH_TOKEN" ]; then
    curl -s -X PUT "${SEARCH_ENDPOINT}/indexes/hotels-sample?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SEARCH_TOKEN" \
        -d "$HOTELS_INDEX_SCHEMA" > /dev/null 2>&1 && echo "✓ Created hotels-sample index" || echo "⚠ Index creation failed or already exists"
else
    echo "⚠ Could not get Azure token, skipping index creation"
fi

# Step 5: Upload sample hotel documents
echo ""
echo "[5/7] Uploading sample hotel documents..."

HOTELS_DATA='{
  "value": [
    {
      "@search.action": "upload",
      "HotelId": "1",
      "HotelName": "Azure Grand Hotel",
      "Description": "Luxury hotel in downtown with modern amenities and stunning city views. Features include rooftop pool, spa, and fine dining restaurant.",
      "Category": "Luxury",
      "Tags": ["pool", "spa", "restaurant", "wifi", "city-view"],
      "Rating": 4.8,
      "Location": {"type": "Point", "coordinates": [-122.131577, 47.678581]},
      "Address": {
        "StreetAddress": "123 Cloud Street",
        "City": "Seattle",
        "StateProvince": "WA",
        "PostalCode": "98101",
        "Country": "USA"
      }
    },
    {
      "@search.action": "upload",
      "HotelId": "2",
      "HotelName": "AI Suites & Conference Center",
      "Description": "Business hotel with state-of-the-art conference facilities and high-speed internet. Perfect for corporate events and tech conferences.",
      "Category": "Business",
      "Tags": ["conference-room", "wifi", "business-center", "parking"],
      "Rating": 4.5,
      "Location": {"type": "Point", "coordinates": [-122.335167, 47.608013]},
      "Address": {
        "StreetAddress": "456 Intelligence Ave",
        "City": "Seattle",
        "StateProvince": "WA",
        "PostalCode": "98102",
        "Country": "USA"
      }
    },
    {
      "@search.action": "upload",
      "HotelId": "3",
      "HotelName": "Cognitive Beach Resort",
      "Description": "Beachfront resort with family-friendly activities, water sports, and kids club. Enjoy sunset views from your private balcony.",
      "Category": "Resort",
      "Tags": ["beach", "pool", "kids-club", "water-sports", "ocean-view"],
      "Rating": 4.7,
      "Location": {"type": "Point", "coordinates": [-122.389695, 47.611595]},
      "Address": {
        "StreetAddress": "789 Reasoning Boulevard",
        "City": "Bellevue",
        "StateProvince": "WA",
        "PostalCode": "98004",
        "Country": "USA"
      }
    }
  ]
}'

if [ -n "$SEARCH_TOKEN" ]; then
    curl -s -X POST "${SEARCH_ENDPOINT}/indexes/hotels-sample/docs/index?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SEARCH_TOKEN" \
        -d "$HOTELS_DATA" > /dev/null 2>&1 && echo "✓ Uploaded 3 sample hotels" || echo "⚠ Document upload failed"
fi

# Step 6: Create Knowledge Source for sample documents
echo ""
echo "[6/7] Creating Knowledge Source for sample documents..."

KB_API_VERSION="2025-11-01-preview"

if [ -n "$SEARCH_TOKEN" ] && [ -n "$STORAGE_CONNECTION_STRING" ] && [ -n "$OPENAI_ENDPOINT" ] && [ -n "$OPENAI_KEY" ]; then
    KNOWLEDGE_SOURCE_JSON=$(cat <<EOF
{
  "name": "sample-documents-ks",
  "kind": "azureBlob",
  "azureBlobParameters": {
    "connectionString": "${STORAGE_CONNECTION_STRING}",
    "containerName": "${CONTAINER_NAME}",
    "ingestionParameters": {
      "embeddingModel": {
        "azureOpenAIParameters": {
          "resourceUri": "${OPENAI_ENDPOINT}",
          "apiKey": "${OPENAI_KEY}",
          "deploymentId": "text-embedding-3-small"
        }
      }
    }
  }
}
EOF
)
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "${SEARCH_ENDPOINT}/knowledgesources/sample-documents-ks?api-version=${KB_API_VERSION}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SEARCH_TOKEN" \
        -d "$KNOWLEDGE_SOURCE_JSON" 2>/dev/null)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "✓ Created Knowledge Source: sample-documents-ks"
    else
        echo "⚠ Knowledge Source creation failed (HTTP $http_code)"
    fi
else
    echo "⚠ Missing credentials for Knowledge Source creation"
    [ -z "$STORAGE_CONNECTION_STRING" ] && echo "    - Storage connection string not available"
    [ -z "$OPENAI_ENDPOINT" ] && echo "    - OpenAI endpoint not available"
    [ -z "$OPENAI_KEY" ] && echo "    - OpenAI API key not available"
fi

# Step 7: Create Knowledge Base
echo ""
echo "[7/7] Creating Knowledge Base..."

if [ -n "$SEARCH_TOKEN" ] && [ -n "$OPENAI_ENDPOINT" ] && [ -n "$OPENAI_KEY" ]; then
    KNOWLEDGE_BASE_JSON=$(cat <<EOF
{
  "name": "sample-knowledge-base",
  "description": "Sample knowledge base with Responsible AI documentation",
  "knowledgeSources": [
    {"name": "sample-documents-ks"}
  ],
  "inferenceParameters": {
    "azureOpenAIParameters": {
      "resourceUri": "${OPENAI_ENDPOINT}",
      "apiKey": "${OPENAI_KEY}",
      "deploymentId": "gpt-4o"
    }
  }
}
EOF
)
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "${SEARCH_ENDPOINT}/knowledgebases/sample-knowledge-base?api-version=${KB_API_VERSION}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SEARCH_TOKEN" \
        -d "$KNOWLEDGE_BASE_JSON" 2>/dev/null)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "✓ Created Knowledge Base: sample-knowledge-base"
    else
        echo "⚠ Knowledge Base creation failed (HTTP $http_code)"
    fi
else
    echo "⚠ Missing credentials for Knowledge Base creation"
fi

# Cleanup
rm -rf /tmp/sample-data

echo ""
echo "======================================"
echo "✓ Sample Data Setup Complete!"
echo "======================================"
echo ""
echo "What was created:"
echo "  1. Blob Storage: $CONTAINER_NAME container with sample PDF"
echo "  2. Search Index: hotels-sample (with 3 documents)"
echo "  3. Knowledge Source: sample-documents-ks (Azure Blob)"
echo "  4. Knowledge Base: sample-knowledge-base"
echo ""
echo "Test queries in the app:"
echo "  - 'What are Microsoft's principles for responsible AI?'"
echo "  - 'Find hotels with a pool in Seattle'"
echo ""
echo "Access the Knowledge Base at:"
echo "  ${SEARCH_ENDPOINT}/knowledgebases/sample-knowledge-base"
echo ""
