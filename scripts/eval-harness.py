#!/usr/bin/env python3
"""
scripts/eval-harness.py — Lightweight evaluation harness for llama-swap aliases (§B.8)

Usage:
    ./scripts/eval-harness.py <alias>          # Run eval suite on specified alias
    ./scripts/eval-harness.py --list           # List available llama-swap aliases
    ./scripts/eval-harness.py --help           # Show this help

Examples:
    ./scripts/eval-harness.py utility-fast
    ./scripts/eval-harness.py doc-vision
    ./scripts/eval-harness.py reasoning-max

Output: JSON results to stdout (redirect to file for archival)
"""

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path
import requests

LLAMA_SWAP_URL = "http://127.0.0.1:8080/v1"

# Simple evaluation prompts for quick smoke testing
EVAL_PROMPTS = [
    {
        "id": "arithmetic_simple",
        "prompt": "Calculate 15 + 27. Reply with just the number.",
        "expected_pattern": r"42",
        "category": "arithmetic"
    },
    {
        "id": "capital_france",
        "prompt": "What is the capital of France? Reply with just the city name.",
        "expected_pattern": r"Paris",
        "category": "knowledge"
    },
    {
        "id": "logic_simple",
        "prompt": "If all cats are animals and all animals need food, do all cats need food? Answer yes or no.",
        "expected_pattern": r"(?i)yes",
        "category": "logic"
    },
    {
        "id": "counting",
        "prompt": "How many letters are in the word 'evaluation'? Reply with just the number.",
        "expected_pattern": r"10",
        "category": "counting"
    },
    {
        "id": "json_format",
        "prompt": 'Reply with valid JSON: {"status": "ok", "value": 123}',
        "expected_pattern": r'"status".*"ok"',
        "category": "format"
    }
]


def list_models():
    """List available llama-swap aliases."""
    try:
        resp = requests.get(f"{LLAMA_SWAP_URL}/models", timeout=5)
        resp.raise_for_status()
        data = resp.json()
        models = [m["id"] for m in data.get("data", [])]
        return models
    except Exception as e:
        print(f"Error listing models: {e}", file=sys.stderr)
        return []


def run_eval_prompt(model: str, prompt_spec: dict, timeout: int = 30) -> dict:
    """Run a single eval prompt against the model."""
    import re

    start = time.time()
    try:
        resp = requests.post(
            f"{LLAMA_SWAP_URL}/chat/completions",
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt_spec["prompt"]}],
                "max_tokens": 128,  # Higher to pass thought-channel (utility-fast Gemma-4-A4B)
                "temperature": 0
            },
            timeout=timeout
        )
        elapsed = time.time() - start

        if resp.status_code != 200:
            return {
                "id": prompt_spec["id"],
                "category": prompt_spec["category"],
                "success": False,
                "error": f"HTTP {resp.status_code}: {resp.text[:200]}",
                "elapsed_s": elapsed
            }

        data = resp.json()
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
        usage = data.get("usage", {})

        # Check if response matches expected pattern
        match = re.search(prompt_spec["expected_pattern"], content)

        return {
            "id": prompt_spec["id"],
            "category": prompt_spec["category"],
            "success": match is not None,
            "response": content,
            "expected_pattern": prompt_spec["expected_pattern"],
            "matched": match is not None,
            "elapsed_s": round(elapsed, 2),
            "tokens": {
                "prompt": usage.get("prompt_tokens", 0),
                "completion": usage.get("completion_tokens", 0),
                "total": usage.get("total_tokens", 0)
            }
        }
    except Exception as e:
        elapsed = time.time() - start
        return {
            "id": prompt_spec["id"],
            "category": prompt_spec["category"],
            "success": False,
            "error": str(e),
            "elapsed_s": round(elapsed, 2)
        }


def run_eval_suite(model: str) -> dict:
    """Run the full eval suite on a model."""
    print(f"Running eval suite on model: {model}", file=sys.stderr)
    print(f"Endpoint: {LLAMA_SWAP_URL}", file=sys.stderr)
    print(f"Prompts: {len(EVAL_PROMPTS)}", file=sys.stderr)
    print("", file=sys.stderr)

    results = []
    for i, prompt_spec in enumerate(EVAL_PROMPTS, 1):
        print(f"[{i}/{len(EVAL_PROMPTS)}] {prompt_spec['id']}...", file=sys.stderr, end=" ")
        result = run_eval_prompt(model, prompt_spec)
        results.append(result)
        status = "✓" if result["success"] else "✗"
        print(f"{status} ({result['elapsed_s']}s)", file=sys.stderr)

    # Aggregate stats
    successes = sum(1 for r in results if r["success"])
    total = len(results)
    accuracy = successes / total if total > 0 else 0.0
    avg_elapsed = sum(r["elapsed_s"] for r in results) / total if total > 0 else 0.0
    total_tokens = sum(r.get("tokens", {}).get("total", 0) for r in results)

    return {
        "model": model,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "endpoint": LLAMA_SWAP_URL,
        "summary": {
            "total_prompts": total,
            "successes": successes,
            "failures": total - successes,
            "accuracy": round(accuracy, 3),
            "avg_elapsed_s": round(avg_elapsed, 2),
            "total_tokens": total_tokens
        },
        "results": results
    }


def main():
    parser = argparse.ArgumentParser(
        description="Lightweight eval harness for llama-swap aliases (§B.8)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("alias", nargs="?", help="llama-swap alias to evaluate")
    parser.add_argument("--list", action="store_true", help="List available aliases")
    parser.add_argument("--output", "-o", help="Output JSON file (default: stdout)")

    args = parser.parse_args()

    if args.list:
        models = list_models()
        if models:
            print("Available aliases:", file=sys.stderr)
            for m in models:
                print(f"  - {m}", file=sys.stderr)
        else:
            print("No models found or llama-swap not running", file=sys.stderr)
            sys.exit(1)
        return

    if not args.alias:
        parser.print_help()
        sys.exit(1)

    # Run eval suite
    eval_results = run_eval_suite(args.alias)

    # Output JSON
    output_json = json.dumps(eval_results, indent=2)
    if args.output:
        Path(args.output).write_text(output_json)
        print(f"\nResults written to {args.output}", file=sys.stderr)
    else:
        print(output_json)

    # Print summary to stderr
    summary = eval_results["summary"]
    print("\n=== Summary ===", file=sys.stderr)
    print(f"Model: {eval_results['model']}", file=sys.stderr)
    print(f"Accuracy: {summary['accuracy']:.1%} ({summary['successes']}/{summary['total_prompts']})", file=sys.stderr)
    print(f"Avg latency: {summary['avg_elapsed_s']}s", file=sys.stderr)
    print(f"Total tokens: {summary['total_tokens']}", file=sys.stderr)


if __name__ == "__main__":
    main()
