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
              <svg width="130" height="28" viewBox="0 0 130 28" xmlns="http://www.w3.org/2000/svg" aria-label="Sonatype" style="display:block;">
                <polygon points="12,1 21,6 21,16 12,21 3,16 3,6" fill="none" stroke="#DAFF02" stroke-width="1.8"/>
                <polygon points="12,5.5 17.5,8.5 17.5,15 12,18 6.5,15 6.5,8.5" fill="#DAFF02"/>
                <text x="29" y="20" font-family="Arial,Helvetica,sans-serif" font-size="17" font-weight="700" fill="#FBFCFA" letter-spacing="-0.3">sonatype</text>
              </svg>
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

        <!-- Expiry callout — brand orange accent -->
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
