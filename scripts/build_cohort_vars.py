"""
Reads every request ever submitted through the portal (status pending or
provisioned) from DynamoDB and writes cohort.auto.tfvars.json so that
`terraform apply` sees the full accumulated set of labs, not just the
newest one. This keeps state consistent across many independent requests
without anyone needing to track lab keys by hand.
"""
import json
import os

import boto3

TABLE = os.environ.get("REQUESTS_TABLE", "digital-labs-requests")

client = boto3.client("dynamodb")


def scan_all(table_name):
    items = []
    kwargs = {"TableName": table_name}
    while True:
        resp = client.scan(**kwargs)
        items.extend(resp.get("Items", []))
        if "LastEvaluatedKey" not in resp:
            break
        kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
    return items


def main():
    items = scan_all(TABLE)
    labs = {}
    for item in items:
        if item.get("status", {}).get("S") == "terminated":
            continue
        lab_key = item["lab_key"]["S"]
        labs[lab_key] = {
            "customer_email": item["customer_email"]["S"],
            "lease_duration": item["lease_duration"]["S"],
        }

    with open("cohort.auto.tfvars.json", "w") as f:
        json.dump({"labs": labs}, f, indent=2)

    print(f"Wrote {len(labs)} lab(s) to cohort.auto.tfvars.json")


if __name__ == "__main__":
    main()
