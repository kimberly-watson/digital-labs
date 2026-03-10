import boto3
import os
from datetime import datetime, timezone

def format_termination_time(iso_string):
    dt = datetime.strptime(iso_string, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return dt.strftime("%A, %B %-d at %-I:%M %p UTC")

def handler(event, context):
    sns       = boto3.client("sns",       region_name=os.environ["APP_REGION"])
    scheduler = boto3.client("scheduler", region_name=os.environ["APP_REGION"])
    customer_email        = os.environ["CUSTOMER_EMAIL"]
    termination_time_raw  = os.environ["TERMINATION_TIME"]
    topic_arn             = os.environ["SNS_TOPIC_ARN"]
    warning_schedule_name = os.environ["WARNING_SCHEDULE_NAME"]
    termination_time = format_termination_time(termination_time_raw)
    subject = "Your Sonatype Digital Lab expires in 48 hours"
    message = (
        "Hello,\n\n"
        "Your Sonatype Digital Lab environment will be automatically shut down in 48 hours.\n\n"
        f"Expiration: {termination_time}\n\n"
        "Please save any work before your lab expires. If you need an extension, contact your Sonatype representative.\n\n"
        "Thank you,\nSonatype Customer Education\n"
    )
    print(f"Sending 48hr warning to: {customer_email}")
    sns.publish(TopicArn=topic_arn, Subject=subject, Message=message)
    try:
        scheduler.delete_schedule(Name=warning_schedule_name)
        print(f"Deleted warning schedule: {warning_schedule_name}")
    except Exception as e:
        print(f"Could not delete warning schedule: {e}")
    return {"statusCode": 200, "body": f"Warning sent to {customer_email}."}
