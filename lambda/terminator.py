import boto3
import os

def handler(event, context):
    """
    Terminates the lab EC2 instance and deletes both EventBridge schedules.
    Triggered by the termination EventBridge schedule at lease expiry.
    """
    ec2 = boto3.client("ec2", region_name=os.environ["AWS_REGION"])
    scheduler = boto3.client("scheduler", region_name=os.environ["AWS_REGION"])

    instance_id = os.environ["INSTANCE_ID"]
    termination_schedule_name = os.environ["TERMINATION_SCHEDULE_NAME"]
    warning_schedule_name = os.environ["WARNING_SCHEDULE_NAME"]

    # Terminate the instance
    print(f"Terminating instance: {instance_id}")
    ec2.terminate_instances(InstanceIds=[instance_id])

    # Delete the termination schedule
    try:
        scheduler.delete_schedule(Name=termination_schedule_name)
        print(f"Deleted termination schedule: {termination_schedule_name}")
    except Exception as e:
        print(f"Could not delete termination schedule: {e}")

    # Delete the warning schedule (may already be deleted after firing)
    try:
        scheduler.delete_schedule(Name=warning_schedule_name)
        print(f"Deleted warning schedule: {warning_schedule_name}")
    except Exception as e:
        print(f"Could not delete warning schedule (may already be gone): {e}")

    return {"statusCode": 200, "body": f"Instance {instance_id} terminated."}
