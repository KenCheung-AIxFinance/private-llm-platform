#!/usr/bin/env python3
"""
scripts/pdf-to-json.py — Extract structured JSON from documents using doc-vision (§B.5)

Demonstrates JSON schema-constrained output from doc-vision VLM via llama-swap.
"""

import argparse
import json
import sys
from pathlib import Path
import requests

LLAMA_SWAP_URL = "http://127.0.0.1:8080/v1"
SCHEMA_PATH = "/srv/z13/vault/samples/schema.json"


def load_schema():
    """Load the JSON schema for validation."""
    with open(SCHEMA_PATH) as f:
        return json.load(f)


def extract_json_from_document(doc_path: str, model: str = "doc-vision") -> dict:
    """
    Extract structured JSON from a document using doc-vision.

    Args:
        doc_path: Path to document (text file as PDF proxy)
        model: llama-swap alias to use (default: doc-vision)

    Returns:
        Extracted JSON dict
    """
    # Read document content
    doc_content = Path(doc_path).read_text()

    # Load schema for prompt
    schema = load_schema()

    # Construct prompt with schema context
    prompt = f"""Extract structured information from this document and return it as JSON.

JSON Schema (follow this structure):
{json.dumps(schema, indent=2)}

Document content:
{doc_content}

Extract the following fields and return ONLY valid JSON (no explanation):
- doc_type: "invoice", "statement", or "receipt"
- doc_number: document identifier
- date: in YYYY-MM-DD format
- vendor_or_entity: vendor/store/entity name
- total_amount: total amount as number
- currency: currency code (default USD)

Return ONLY the JSON object, nothing else."""

    print(f"Processing {Path(doc_path).name}...", file=sys.stderr)

    # Call llama-swap with JSON mode
    resp = requests.post(
        f"{LLAMA_SWAP_URL}/chat/completions",
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 512,
            "temperature": 0,
            "response_format": {"type": "json_object"}  # JSON-constrained output
        },
        timeout=60
    )

    if resp.status_code != 200:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:200]}")

    data = resp.json()
    content = data.get("choices", [{}])[0].get("message", {}).get("content", "")

    # Parse JSON response
    try:
        extracted = json.loads(content)
        return extracted
    except json.JSONDecodeError as e:
        print(f"Failed to parse JSON: {e}", file=sys.stderr)
        print(f"Raw content: {content}", file=sys.stderr)
        raise


def validate_against_schema(data: dict, schema: dict) -> tuple[bool, list]:
    """
    Validate extracted JSON against schema.

    Returns:
        (is_valid, errors)
    """
    from jsonschema import validate, ValidationError

    try:
        validate(instance=data, schema=schema)
        return True, []
    except ValidationError as e:
        return False, [str(e)]


def main():
    parser = argparse.ArgumentParser(description="Extract JSON from documents via doc-vision (§B.5)")
    parser.add_argument("documents", nargs="+", help="Document files to process")
    parser.add_argument("--model", default="doc-vision", help="llama-swap alias (default: doc-vision)")
    parser.add_argument("--output-dir", default="/srv/z13/vault/samples", help="Output directory for JSON files")
    parser.add_argument("--validate", action="store_true", help="Validate output against schema")

    args = parser.parse_args()

    # Load schema
    schema = load_schema()
    print(f"Loaded schema from {SCHEMA_PATH}", file=sys.stderr)
    print(f"Required fields: {schema['required']}", file=sys.stderr)
    print("", file=sys.stderr)

    results = []

    for doc_path in args.documents:
        try:
            # Extract JSON
            extracted = extract_json_from_document(doc_path, args.model)

            # Validate if requested
            if args.validate:
                is_valid, errors = validate_against_schema(extracted, schema)
                if is_valid:
                    print(f"  ✓ Valid JSON", file=sys.stderr)
                else:
                    print(f"  ✗ Validation failed: {errors}", file=sys.stderr)

            # Write output
            doc_name = Path(doc_path).stem
            output_path = Path(args.output_dir) / f"{doc_name}.json"
            output_path.write_text(json.dumps(extracted, indent=2))
            print(f"  → {output_path}", file=sys.stderr)
            print("", file=sys.stderr)

            results.append({
                "source": doc_path,
                "output": str(output_path),
                "data": extracted
            })

        except Exception as e:
            print(f"  ✗ Error: {e}", file=sys.stderr)
            print("", file=sys.stderr)
            results.append({
                "source": doc_path,
                "error": str(e)
            })

    # Summary
    print("=== Summary ===", file=sys.stderr)
    successes = sum(1 for r in results if "data" in r)
    print(f"Processed: {len(results)}", file=sys.stderr)
    print(f"Successful: {successes}", file=sys.stderr)
    print(f"Failed: {len(results) - successes}", file=sys.stderr)

    # Output results as JSON
    print(json.dumps({"results": results}, indent=2))


if __name__ == "__main__":
    main()
