import os
import sys
import argparse
from pathlib import Path
from azure.identity import InteractiveBrowserCredential
from azure.storage.blob import BlobServiceClient
from dotenv import load_dotenv

load_dotenv(override=True)


def env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        print(f"Missing env var: {name}", file=sys.stderr)
        sys.exit(1)
    return value


def main():
    parser = argparse.ArgumentParser(
        description="Interactive dump of an Azure Blob Storage container using Entra ID auth"
    )
    parser.add_argument(
        "--out",
        default="../data/blob",
        help="Output directory (default: ./data)",
    )
    args = parser.parse_args()

    tenant_id = env("AZURE_TENANT_ID")
    account_name = env("AZURE_STORAGE_ACCOUNT")
    container_name = env("AZURE_STORAGE_CONTAINER")

    base_dir = Path(args.out)
    output_dir = base_dir / container_name
    output_dir.mkdir(parents=True, exist_ok=True)

    print("▶ Opening browser for Entra ID login…")

    credential = InteractiveBrowserCredential(
        tenant_id=tenant_id
    )

    account_url = f"https://{account_name}.blob.core.windows.net"
    blob_service = BlobServiceClient(
        account_url=account_url,
        credential=credential
    )

    container_client = blob_service.get_container_client(container_name)

    print(
        f"▶ Downloading container '{container_name}' "
        f"from storage account '{account_name}'"
    )
    print(f"▶ Output folder: {output_dir.resolve()}")

    for blob in container_client.list_blobs():
        local_path = output_dir / blob.name
        local_path.parent.mkdir(parents=True, exist_ok=True)

        print(f"  ↳ {blob.name}")

        with open(local_path, "wb") as f:
            stream = container_client.download_blob(blob.name)
            f.write(stream.readall())

    print("\n✅ Container dump completed successfully.")


if __name__ == "__main__":
    main()
