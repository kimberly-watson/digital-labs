import boto3
import os
import urllib.request
import time

ec2 = boto3.client("ec2", region_name=os.environ["AWS_REGION"])
ses = boto3.client("ses", region_name=os.environ["AWS_REGION"])

MAX_WAIT_SECONDS = 600
POLL_INTERVAL    = 30


def wait_for_portal(ip):
    url = f"http://{ip}/"
    deadline = time.time() + MAX_WAIT_SECONDS
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(urllib.request.Request(url), timeout=5) as resp:
                if resp.status == 200:
                    print(f"Portal is up at {url}")
                    return True
        except Exception as e:
            print(f"Portal not ready ({e}), retrying in {POLL_INTERVAL}s...")
        time.sleep(POLL_INTERVAL)
    print(f"Portal not ready after {MAX_WAIT_SECONDS}s, sending email anyway.")
    return False


def build_html(lab_url, nexus_url, iq_url, termination_time):
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Your Sonatype Digital Lab is Ready</title>
</head>
<body style="margin:0;padding:0;background:#f4f6f8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f8;padding:40px 0;">
  <tr><td align="center">
    <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">

      <!-- Header -->
      <tr><td style="background:#1a3c6e;padding:32px 40px;">
        <p style="margin:0;font-size:11px;font-weight:700;letter-spacing:3px;text-transform:uppercase;color:#7eb8e8;">SONATYPE CUSTOMER EDUCATION</p>
        <h1 style="margin:8px 0 0;font-size:22px;font-weight:700;color:#ffffff;">Your Digital Lab is Ready</h1>
      </td></tr>

      <!-- Body -->
      <tr><td style="padding:36px 40px;">
        <p style="margin:0 0 20px;font-size:15px;line-height:1.6;color:#333;">
          Your Sonatype Digital Lab environment has been provisioned and is ready to use.
          Click the button below to open your lab portal.
        </p>

        <!-- CTA button -->
        <table cellpadding="0" cellspacing="0" style="margin:0 0 32px;">
          <tr><td style="background:#00b4d8;border-radius:6px;">
            <a href="{lab_url}" style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">Open Lab Portal &rarr;</a>
          </td></tr>
        </table>

        <!-- Product cards -->
        <p style="margin:0 0 12px;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#888;">Available Products</p>
        <table width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 28px;">
          <tr>
            <td width="48%" style="background:#f0f7ff;border:1px solid #d0e4f7;border-radius:6px;padding:16px 18px;">
              <p style="margin:0 0 4px;font-size:13px;font-weight:700;color:#1a3c6e;">&#128230; Nexus Repository CE</p>
              <p style="margin:0 0 8px;font-size:12px;color:#666;">Browse and manage artifacts</p>
              <a href="{nexus_url}" style="font-size:12px;color:#00b4d8;text-decoration:none;font-weight:600;">Open &rarr;</a>
            </td>
            <td width="4%"></td>
            <td width="48%" style="background:#f0f7ff;border:1px solid #d0e4f7;border-radius:6px;padding:16px 18px;">
              <p style="margin:0 0 4px;font-size:13px;font-weight:700;color:#1a3c6e;">&#128269; IQ Server</p>
              <p style="margin:0 0 8px;font-size:12px;color:#666;">Lifecycle &amp; Firewall</p>
              <a href="{iq_url}" style="font-size:12px;color:#00b4d8;text-decoration:none;font-weight:600;">Open &rarr;</a>
            </td>
          </tr>
        </table>

        <!-- Credentials -->
        <table width="100%" cellpadding="0" cellspacing="0" style="background:#f8f9fa;border:1px solid #e0e0e0;border-radius:6px;margin:0 0 28px;">
          <tr><td style="padding:16px 20px;">
            <p style="margin:0 0 8px;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#888;">Default Credentials</p>
            <p style="margin:0;font-size:14px;color:#333;">
              Username: <span style="font-family:monospace;background:#e8e8e8;padding:2px 6px;border-radius:3px;font-size:13px;">admin</span>
              &nbsp;&nbsp;
              Password: <span style="font-family:monospace;background:#e8e8e8;padding:2px 6px;border-radius:3px;font-size:13px;">admin123</span>
            </p>
          </td></tr>
        </table>

        <!-- Expiry notice -->
        <table width="100%" cellpadding="0" cellspacing="0" style="background:#fff8e1;border:1px solid #ffe082;border-radius:6px;margin:0 0 20px;">
          <tr><td style="padding:14px 18px;">
            <p style="margin:0;font-size:13px;color:#7a5c00;">
              <strong>&#9200; Lab Expiry:</strong> This environment will be automatically shut down on <strong>{termination_time} UTC</strong>.
              Please save any work before then. Contact your Sonatype representative if you need an extension.
            </p>
          </td></tr>
        </table>

        <p style="margin:0;font-size:13px;color:#999;line-height:1.6;">
          A Lab Tutor AI assistant is available via the chat bubble on your portal page &mdash; ask it anything about Nexus Repository or IQ Server.
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
    instance_id      = os.environ["INSTANCE_ID"]
    customer_email   = os.environ["CUSTOMER_EMAIL"]
    termination_time = os.environ["TERMINATION_TIME"]
    from_email       = os.environ["SES_FROM_EMAIL"]

    resp = ec2.describe_instances(InstanceIds=[instance_id])
    ip = resp["Reservations"][0]["Instances"][0].get("PublicIpAddress", "unavailable")
    lab_url   = f"http://{ip}"
    nexus_url = f"http://{ip}:8081"
    iq_url    = f"http://{ip}:8070"

    wait_for_portal(ip)

    subject   = "Your Sonatype Digital Lab is Ready"
    text_body = (
        f"Your Sonatype Digital Lab is ready.\n\n"
        f"Lab Portal: {lab_url}\n\n"
        f"Products:\n"
        f"  Nexus Repository: {nexus_url}\n"
        f"  IQ Server:        {iq_url}\n\n"
        f"Default credentials: admin / admin123\n\n"
        f"Your lab will be automatically terminated on {termination_time} UTC.\n"
        f"Need more time? Contact your Sonatype representative before expiry.\n"
    )
    html_body = build_html(lab_url, nexus_url, iq_url, termination_time)

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

    print(f"Welcome email sent to {customer_email} for instance {instance_id} at {ip}")
    return {"status": "ok"}
