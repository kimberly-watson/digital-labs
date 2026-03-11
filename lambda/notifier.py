import boto3
import os
from datetime import datetime, timezone


def format_termination_time(iso_string):
    dt = datetime.strptime(iso_string, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return dt.strftime("%A, %B %-d at %-I:%M %p UTC")


def build_html(lab_url, termination_time):
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Your Sonatype Digital Lab Expires in 48 Hours</title>
</head>
<body style="margin:0;padding:0;background:#f4f6f8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f8;padding:40px 0;">
  <tr><td align="center">
    <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">

      <!-- Header: Sonatype brand dark navy + blue accent -->
      <tr><td style="background:#090B2F;padding:28px 40px 24px;border-bottom:3px solid #2D36EC;">
        <table cellpadding="0" cellspacing="0">
          <tr>
            <td style="vertical-align:middle;">
              <img src=\"data:image/png;base64,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\" height=\"56\" alt=\"Sonatype\" style=\"display:block;\">
            </td>
          </tr>
        </table>
        <p style="margin:14px 0 0;font-size:11px;font-weight:700;letter-spacing:3px;text-transform:uppercase;color:rgba(255,255,255,0.55);">CUSTOMER EDUCATION</p>
        <h1 style="margin:6px 0 0;font-size:22px;font-weight:700;color:#ffffff;">&#9200; Your Lab Expires in 48 Hours</h1>
      </td></tr>

      <!-- Body -->
      <tr><td style="padding:36px 40px;">
        <p style="margin:0 0 20px;font-size:15px;line-height:1.6;color:#333;">
          Your Sonatype Digital Lab environment will be automatically shut down in <strong>48 hours</strong>.
          Please save any work before then.
        </p>

        <!-- Expiry callout â€” brand orange accent -->
        <table width="100%" cellpadding="0" cellspacing="0"
               style="background:#fff4f1;border-left:4px solid #FE572A;border-radius:0 6px 6px 0;margin:0 0 28px;">
          <tr><td style="padding:16px 20px;">
            <p style="margin:0 0 4px;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#FE572A;">Expiration</p>
            <p style="margin:0;font-size:16px;font-weight:700;color:#111;">{termination_time}</p>
          </td></tr>
        </table>

        <!-- CTA button -->
        <table cellpadding="0" cellspacing="0" style="margin:0 0 28px;">
          <tr><td style="background:#2D36EC;border-radius:6px;">
            <a href="{lab_url}" style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">Return to Lab Portal &rarr;</a>
          </td></tr>
        </table>

        <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#333;">
          If you need additional time, contact your Sonatype representative
          <strong>before the expiration date</strong> to request an extension.
        </p>
        <p style="margin:0;font-size:13px;color:#999;line-height:1.6;">
          After expiration, the environment will be permanently deleted and cannot be recovered.
        </p>
      </td></tr>

      <!-- Footer -->
      <tr><td style="background:#f0f0f0;padding:20px 40px;border-top:1px solid #e0e0e0;">
        <p style="margin:0;font-size:12px;color:#999;text-align:center;">
          Sonatype Customer Education &nbsp;&bull;&nbsp; This is an automated message &nbsp;&bull;&nbsp; Do not reply to this email
        </p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>"""


def handler(event, context):
    ses       = boto3.client("ses",       region_name=os.environ["APP_REGION"])
    scheduler = boto3.client("scheduler", region_name=os.environ["APP_REGION"])

    customer_email        = os.environ["CUSTOMER_EMAIL"]
    instance_id           = os.environ["INSTANCE_ID"]
    termination_time_raw  = os.environ["TERMINATION_TIME"]
    from_email            = os.environ["SES_FROM_EMAIL"]
    warning_schedule_name = os.environ["WARNING_SCHEDULE_NAME"]

    ec2 = boto3.client("ec2", region_name=os.environ["APP_REGION"])
    resp = ec2.describe_instances(InstanceIds=[instance_id])
    ip = resp["Reservations"][0]["Instances"][0].get("PublicIpAddress", "unavailable")
    lab_url = f"http://{ip}"

    termination_time = format_termination_time(termination_time_raw)

    subject   = "Your Sonatype Digital Lab expires in 48 hours"
    text_body = (
        "Hello,\n\n"
        "Your Sonatype Digital Lab environment will be automatically shut down in 48 hours.\n\n"
        f"Expiration: {termination_time}\n\n"
        f"Lab Portal: {lab_url}\n\n"
        "Please save any work before your lab expires. "
        "If you need an extension, contact your Sonatype representative.\n\n"
        "Thank you,\nSonatype Customer Education\n"
    )
    html_body = build_html(lab_url, termination_time)

    print(f"Sending 48hr warning to: {customer_email}")
    ses.send_email(
        Source=from_email,
        Destination={"ToAddresses": [customer_email]},
        Message={
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {
                "Text": {"Data": text_body, "Charset": "UTF-8"},
                "Html": {"Data": html_body,  "Charset": "UTF-8"},
            }
        }
    )

    try:
        scheduler.delete_schedule(Name=warning_schedule_name)
        print(f"Deleted warning schedule: {warning_schedule_name}")
    except Exception as e:
        print(f"Could not delete warning schedule: {e}")

    return {"statusCode": 200, "body": f"Warning sent to {customer_email}."}
