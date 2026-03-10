variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type. t3.large (8GB RAM) minimum - required to run both Nexus and IQ Server."
  type        = string
  default     = "t3.large"
}

variable "volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "ssm_parameter_path" {
  description = "SSM Parameter Store path where the base64-encoded Sonatype license is stored"
  type        = string
  default     = "/digital-labs/sonatype-license"
}

variable "lab_name" {
  description = "Name tag applied to the EC2 instance"
  type        = string
  default     = "digital-labs-instance"
}

variable "lease_duration" {
  description = "How long the lab instance should run before automatic termination. Options: 1w, 2w, 3w, 1mo. Set by Sonatype personnel at deploy time."
  type        = string
  default     = "1w"

  validation {
    condition     = contains(["1w", "2w", "3w", "1mo"], var.lease_duration)
    error_message = "lease_duration must be one of: 1w, 2w, 3w, 1mo."
  }
}

variable "customer_email" {
  description = "Customer email address for lab expiry notifications. Set by Sonatype personnel at deploy time."
  type        = string
  default     = ""
}
