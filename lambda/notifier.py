import boto3
import os

def handler(event, context):
    """
    Sends a 48-hour warning email to the customer via SNS.
    Triggered by the warning EventBridge schedule 48hr before lease expiry.
    Also deletes itself after firing (one-shot schedule).
    """
    sns = boto3.client("sns", region_name=os.environ["AWS_REGION"])
    scheduler = boto3.client("scheduler", region_name=os.environ["AWS_REGION"])

    customer_email = os.environ["CUSTOMER_EMAIL"]
    termination_time = os.environ["TERMINATION_TIME"]
    instance_id = os.environ["INSTANCE_ID"]
    topic_arn = os.environ["SNS_TOPIC_ARN"]
    warning_schedule_name = os.environ["WARNING_SCHEDULE_NAME"]

    subject = "Your Sonatype Digital Lab expires in 48 hours"
    message = f"""Hello,

Your Sonatype Digital Lab environment will be automatically shut down in 48 hours.

Termination time: {termination_time} UTC
Instance: {instance_id}

Please save any work before your lab expires. If you need an extension, contact your Sonatype representative.

Thank you,
Sonatype Customer Education
"""

    print(f"Sending 48hr warning to: {customer_email}")
    sns.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message
    )

    # Self-delete this schedule after firing
    try:
        scheduler.delete_schedule(Name=warning_schedule_name)
        print(f"Deleted warning schedule: {warning_schedule_name}")
    except Exception as e:
        print(f"Could not delete warning schedule: {e}")

    return {"statusCode": 200, "body": f"Warning sent to {customer_email}."}
