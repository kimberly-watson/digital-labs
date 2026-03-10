variable "lab_key" {
  description = "Short unique identifier for this lab (e.g. 'alice', 'cohort-01'). Used in resource names and SSM paths."
  type        = string
}

variable "customer_email" {
  description = "Customer email for welcome and warning notifications."
  type        = string
}

variable "lease_duration" {
  description = "Lab lease length: 1w, 2w, 3w, or 1mo."
  type        = string
  validation {
    condition     = contains(["1w", "2w", "3w", "1mo"], var.lease_duration)
    error_message = "lease_duration must be one of: 1w, 2w, 3w, 1mo."
  }
}

variable "lab_name" {
  description = "Name tag for the EC2 instance."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "volume_size_gb" {
  description = "Root EBS volume size in GB."
  type        = number
}

variable "ses_from_email" {
  description = "SES verified sender address."
  type        = string
}

# Shared resources passed in from root

variable "lambda_exec_role_arn" {
  description = "ARN of the shared Lambda execution IAM role."
  type        = string
}

variable "scheduler_exec_role_arn" {
  description = "ARN of the shared EventBridge Scheduler IAM role."
  type        = string
}

variable "security_group_id" {
  description = "ID of the shared lab security group."
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the shared EC2 IAM instance profile."
  type        = string
}
