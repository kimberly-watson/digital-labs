import boto3
import os

def handler(event, context):
    """
    Terminates the lab EC2 instance and deletes all three EventBridge schedules.
    Triggered by the termination EventBridge schedule at lease expiry.
    """
    ec2 = boto3.client("ec2", region_name=os.environ["APP_REGION"])
    scheduler = boto3.client("scheduler", region_name=os.environ["APP_REGION"])

    instance_id = os.environ["INSTANCE_ID"]
    schedules_to_delete = [
        os.environ["TERMINATION_SCHEDULE_NAME"],
        os.environ["WARNING_SCHEDULE_NAME"],
        os.environ.get("WELCOME_SCHEDULE_NAME", ""),
    ]

    # Terminate the instance
    print(f"Terminating instance: {instance_id}")
    ec2.terminate_instances(InstanceIds=[instance_id])

    # Delete all schedules (some may already be gone - that's fine)
    for name in schedules_to_delete:
        if not name:
            continue
        try:
            scheduler.delete_schedule(Name=name)
            print(f"Deleted schedule: {name}")
        except Exception as e:
            print(f"Could not delete schedule {name} (may already be gone): {e}")

    return {"statusCode": 200, "body": f"Instance {instance_id} terminated."}
