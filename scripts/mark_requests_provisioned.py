"""
After a successful terraform apply, flips any 'pending' request in
DynamoDB to 'provisioned' so the next build's scan doesn't need to
distinguish new vs. existing labs by any means other than this table.
"""
import os

import boto3

TABLE = os.environ.get("REQUESTS_TABLE", "digital-labs-requests")

client = boto3.client("dynamodb")


def main():
    resp = client.scan(TableName=TABLE)
    for item in resp.get("Items", []):
        if item.get("status", {}).get("S") == "pending":
            client.update_item(
                TableName=TABLE,
                Key={"lab_key": item["lab_key"]},
                UpdateExpression="SET #s = :provisioned",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={":provisioned": {"S": "provisioned"}},
            )


if __name__ == "__main__":
    main()
