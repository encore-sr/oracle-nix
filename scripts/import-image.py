#!/usr/bin/env python3
"""Imports a NixOS qcow2 into OCI as a custom image launchable on Ampere A1.

This exists because:
  `oci compute image import` cannot set launchOptions, and importing as
  PARAVIRTUALIZED hardcodes BIOS firmware, which then breaks aarch64
  UEFI boot.

  NATIVE gives UEFI but ISCSI boot volumes that hang generic initramfs.

  The only working method is launchMode=CUSTOM with explicit
  firmware=UEFI_64 + all-Paravirtualized.

References:
  - https://gist.github.com/PeronGH/053ae2b595d0e965f19eeaa14b2384e0
  - https://www.dima.pm/proxmox-ve-9-2-arm64-on-oracle-cloud/

Usage:
  python3 scripts/import-image.py result/nixos.qcow2 \
    --config /path/to/oci/config \
    --bucket nixos-images \
    --image-name nixos-aarch64-abc123 \
    --shape VM.Standard.A1.Flex

Requires OCI config with API key. Can also use env vars for CI:
  OCI_USER, OCI_FINGERPRINT, OCI_TENANCY, OCI_REGION, OCI_PRIVATE_KEY (pem content)
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import oci
import requests
from oci.config import from_file as oci_config_from_file
from oci.signer import Signer
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


def make_session() -> requests.Session:
    s = requests.Session()
    retries = Retry(
        total=10,
        backoff_factor=3,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["HEAD", "GET", "PUT", "POST", "DELETE", "OPTIONS", "TRACE"],
        raise_on_status=False,
    )
    s.mount("https://", HTTPAdapter(max_retries=retries))
    return s


def upload_with_retry(
    session: requests.Session,
    signer,
    obj: str,
    ns: str,
    bucket: str,
    object_name: str,
    filepath: Path,
) -> None:
    url = f"{obj}/n/{ns}/b/{bucket}/o/{object_name}"
    file_size = filepath.stat().st_size
    size_gb = file_size / 1e9
    print(f"uploading {object_name} ({size_gb:.2f} GB) with retries...")

    for attempt in range(10):
        try:
            with open(filepath, "rb") as f:
                r = session.put(
                    url,
                    auth=signer,
                    data=f,
                    headers={"Content-Type": "application/octet-stream"},
                    timeout=1800,
                )
            if r.status_code >= 400:
                print(f"  attempt {attempt + 1} error: {r.status_code} {r.text}")
                if r.status_code == 404:
                    sys.exit(f"upload failed: bucket/object not found")
            else:
                print("upload done")
                return
        except (
            requests.exceptions.ConnectionError,
            requests.exceptions.ChunkedEncodingError,
            requests.exceptions.Timeout,
        ) as e:
            print(f"  attempt {attempt + 1} connection error: {e}")
        if attempt < 9:
            wait = 10 * (attempt + 1)
            print(f"  waiting {wait}s before retry...")
            time.sleep(wait)

    sys.exit("upload failed after 10 attempts")


def load_config(args) -> dict:
    """Load OCI config from file or env vars."""
    if args.config and os.path.exists(args.config):
        return oci_config_from_file(args.config)

    # Build from env vars (for CI)
    required = [
        "OCI_USER",
        "OCI_FINGERPRINT",
        "OCI_TENANCY",
        "OCI_REGION",
        "OCI_PRIVATE_KEY",
    ]
    if all(os.environ.get(k) for k in required):
        key_path = "/tmp/oci_api_key.pem"
        with open(key_path, "w") as f:
            f.write(os.environ["OCI_PRIVATE_KEY"])
        os.chmod(key_path, 0o600)
        return {
            "user": os.environ["OCI_USER"],
            "fingerprint": os.environ["OCI_FINGERPRINT"],
            "tenancy": os.environ["OCI_TENANCY"],
            "region": os.environ["OCI_REGION"],
            "key_file": key_path,
            "compartment_id": os.environ.get(
                "OCI_COMPARTMENT_ID", os.environ["OCI_TENANCY"]
            ),
        }

    sys.exit(
        "No OCI config found. Please use --config or set env vars: OCI_USER, OCI_FINGERPRINT, OCI_TENANCY, OCI_REGION, OCI_PRIVATE_KEY"
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("qcow2", type=Path)
    ap.add_argument("--bucket", default="nixos-images")
    ap.add_argument("--image-name", default="nixos-aarch64")
    ap.add_argument("--shape", default="VM.Standard.A1.Flex")
    ap.add_argument(
        "--config",
        default=os.environ.get("OCI_CONFIG", str(Path.home() / ".oci/config")),
    )
    args = ap.parse_args()

    if not args.qcow2.is_file():
        sys.exit(f"not a file: {args.qcow2}")

    cfg = load_config(args)
    signer = Signer(
        tenancy=cfg["tenancy"],
        user=cfg["user"],
        fingerprint=cfg["fingerprint"],
        private_key_file_location=cfg["key_file"],
    )
    region = cfg["region"]
    iaas = f"https://iaas.{region}.oraclecloud.com"
    obj = f"https://objectstorage.{region}.oraclecloud.com"
    compartment = cfg.get("compartment_id") or cfg["tenancy"]

    session = make_session()

    ns = session.get(f"{obj}/n", auth=signer, timeout=30).text.strip('"')
    print(f"namespace: {ns}")

    r = session.post(
        f"{obj}/n/{ns}/b/",
        auth=signer,
        json={"name": args.bucket, "compartmentId": compartment},
        timeout=30,
    )
    if r.status_code not in (200, 409):
        sys.exit(f"bucket create failed: {r.status_code} {r.text}")
    print(f"bucket ok: {args.bucket}")

    size_gb = args.qcow2.stat().st_size / 1e9
    print(f"uploading {args.qcow2.name} ({size_gb:.2f} GB)...")
    upload_with_retry(
        session, signer, obj, ns, args.bucket, args.qcow2.name, args.qcow2
    )
    print("upload done")

    body = {
        "compartmentId": compartment,
        "displayName": args.image_name,
        "launchMode": "CUSTOM",
        "launchOptions": {
            "bootVolumeType": "PARAVIRTUALIZED",
            "networkType": "PARAVIRTUALIZED",
            "remoteDataVolumeType": "PARAVIRTUALIZED",
            "firmware": "UEFI_64",
            "isConsistentVolumeNamingEnabled": False,
            "isPvEncryptionInTransitEnabled": False,
        },
        "imageSourceDetails": {
            "sourceType": "objectStorageTuple",
            "namespaceName": ns,
            "bucketName": args.bucket,
            "objectName": args.qcow2.name,
            "sourceImageType": "QCOW2",
            "operatingSystem": "Linux",
            "operatingSystemVersion": "26.05",
        },
    }
    r = session.post(f"{iaas}/20160918/images", auth=signer, json=body, timeout=60)
    if r.status_code >= 400:
        sys.exit(f"image create failed: {r.status_code} {r.text}")
    image_id = r.json()["id"]
    print("import started:", image_id)

    while True:
        img = session.get(
            f"{iaas}/20160918/images/{image_id}", auth=signer, timeout=30
        ).json()
        state = img["lifecycleState"]
        print("  state:", state, flush=True)
        if state == "AVAILABLE":
            break
        if state in ("FAILED", "DELETED"):
            sys.exit(f"import {state}:\n{json.dumps(img, indent=2)}")
        time.sleep(20)

    fw = img.get("launchOptions", {}).get("firmware")
    assert fw == "UEFI_64", f"firmware stuck as {fw!r}; the instance would not boot"

    compute_client = oci.core.ComputeClient(cfg, signer=signer)
    try:
        compute_client.add_image_shape_compatibility_entry(
            image_id=image_id, shape_name=args.shape
        )
        print(f"shape compat added: {args.shape}")
    except oci.exceptions.ServiceError as e:
        print(f"shape compat warning: {e.status} {e.code} {e.message}")

    print(f"firmware confirmed as UEFI_64; shape compat added: {args.shape}")
    print(f"IMAGE_ID={image_id}")


if __name__ == "__main__":
    main()
