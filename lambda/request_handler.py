import json
import os
import re
import time
import uuid
import urllib.parse

import boto3

dynamodb = boto3.client("dynamodb")
codebuild = boto3.client("codebuild")
ssm = boto3.client("ssm")
ses = boto3.client("ses")

REQUESTS_TABLE = os.environ["REQUESTS_TABLE"]
CODEBUILD_PROJECT = os.environ["CODEBUILD_PROJECT"]
ACCESS_CODE_PARAM = os.environ["ACCESS_CODE_PARAM"]
SES_FROM_EMAIL = os.environ["SES_FROM_EMAIL"]
NOTIFY_EMAIL = os.environ["NOTIFY_EMAIL"]

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
VALID_LEASES = {"1w", "2w", "3w", "1mo"}

FORM_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Digital Labs - Request a Lab</title>
<style>
  body {{ font-family: -apple-system, Helvetica, Arial, sans-serif; background: #F1F5ED; color: #090B2F; margin: 0; }}
  .header {{ background: #090B2F; color: #FBFCFA; padding: 32px 40px; }}
  .header h1 {{ margin: 0; font-size: 24px; }}
  .pill {{ display: inline-block; background: #DAFF02; color: #090B2F; font-weight: 700; font-size: 12px; padding: 4px 10px; border-radius: 12px; margin-top: 10px; }}
  .card {{ background: #FBFCFA; max-width: 480px; margin: 32px auto; padding: 32px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }}
  label {{ display: block; font-weight: 600; margin-top: 16px; margin-bottom: 6px; font-size: 14px; }}
  input, select {{ width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px; box-sizing: border-box; }}
  button {{ margin-top: 24px; width: 100%; background: #2D36EC; color: #FBFCFA; border: none; padding: 12px; font-size: 15px; font-weight: 700; border-radius: 4px; cursor: pointer; }}
  button:hover {{ background: #FE572A; }}
  .msg {{ margin-top: 16px; font-size: 14px; }}
</style>
</head>
<body>
  <div class="header">
    <h1>Digital Labs</h1>
    <div class="pill">INTERNAL REQUEST FORM</div>
  </div>
  <div class="card">
    {message}
    <form method="POST" action="/submit">
      <label>Access code</label>
      <input type="password" name="access_code" required>
      <label>Customer email</label>
      <input type="email" name="customer_email" required>
      <label>Lease duration</label>
      <select name="lease_duration">
        <option value="1w">1 week</option>
        <option value="2w">2 weeks</option>
        <option value="3w">3 weeks</option>
        <option value="1mo">1 month</option>
      </select>
      <button type="submit">Request Lab</button>
    </form>
  </div>
</body>
</html>
"""


def _html_response(status, message=""):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "text/html"},
        "body": FORM_HTML.format(message=message),
    }


def _parse_form_body(event):
    body = event.get("body", "") or ""
    if event.get("isBase64Encoded"):
        import base64
        body = base64.b64decode(body).decode("utf-8")
    return {k: v[0] for k, v in urllib.parse.parse_qs(body).items()}


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if method == "GET":
        return _html_response(200)

    if method == "POST":
        fields = _parse_form_body(event)

        access_code = fields.get("access_code", "")
        expected = ssm.get_parameter(Name=ACCESS_CODE_PARAM, WithDecryption=True)["Parameter"]["Value"]
        if access_code != expected:
            return _html_response(403, '<p class="msg" style="color:#FE572A;">Incorrect access code.</p>')

        customer_email = fields.get("customer_email", "").strip()
        lease_duration = fields.get("lease_duration", "")

        if not EMAIL_RE.match(customer_email):
            return _html_response(400, '<p class="msg" style="color:#FE572A;">Enter a valid customer email.</p>')
        if lease_duration not in VALID_LEASES:
            return _html_response(400, '<p class="msg" style="color:#FE572A;">Invalid lease duration.</p>')

        lab_key = f"lab-{uuid.uuid4().hex[:8]}"

        dynamodb.put_item(
            TableName=REQUESTS_TABLE,
            Item={
                "lab_key": {"S": lab_key},
                "customer_email": {"S": customer_email},
                "lease_duration": {"S": lease_duration},
                "requested_at": {"N": str(int(time.time()))},
                "status": {"S": "pending"},
            },
        )

        codebuild.start_build(
            projectName=CODEBUILD_PROJECT,
            environmentVariablesOverride=[
                {"name": "TRIGGERED_BY", "value": lab_key, "type": "PLAINTEXT"},
            ],
        )

        try:
            ses.send_email(
                Source=SES_FROM_EMAIL,
                Destination={"ToAddresses": [NOTIFY_EMAIL]},
                Message={
                    "Subject": {"Data": f"[Digital Labs] New lab request: {customer_email}", "Charset": "UTF-8"},
                    "Body": {"Text": {
                        "Data": f"New lab request submitted.\n\nLab ID: {lab_key}\nCustomer: {customer_email}\nLease: {lease_duration}\n\nProvisioning now, ready in ~10-15 minutes.",
                        "Charset": "UTF-8",
                    }},
                },
            )
        except Exception:
            pass  # Notification failure shouldn't block the actual request

        return _html_response(
            200,
            f'<p class="msg" style="color:#2D36EC;">Request submitted (ID: {lab_key}). '
            f'The lab is provisioning now, the customer will receive a welcome email once it is ready (~10 min).</p>',
        )

    return {"statusCode": 405, "body": "Method not allowed"}
