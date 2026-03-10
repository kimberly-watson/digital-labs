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
  description = "Name tag for the EC2 instance (single-lab mode only)"
  type        = string
  default     = "digital-labs-instance"
}

variable "lease_duration" {
  description = "Lab lease length for single-lab mode: 1w, 2w, 3w, or 1mo."
  type        = string
  default     = "1w"

  validation {
    condition     = contains(["1w", "2w", "3w", "1mo"], var.lease_duration)
    error_message = "lease_duration must be one of: 1w, 2w, 3w, 1mo."
  }
}

variable "customer_email" {
  description = "Customer email for single-lab mode. Leave empty when using var.labs (cohort mode)."
  type        = string
  default     = ""
}

variable "ses_from_email" {
  description = "Verified SES sender address (e.g. digital-labs@sonatype.com). Must be verified in AWS SES before deploying."
  type        = string
  default     = "digital-labs@sonatype.com"
}

# ---------------------------------------------------------------------------
# Cohort mode: define multiple labs in one apply
# ---------------------------------------------------------------------------
# Example cohort.tfvars:
#   labs = {
#     "alice" = { customer_email = "alice@company.com", lease_duration = "2w" }
#     "bob"   = { customer_email = "bob@company.com",   lease_duration = "2w" }
#   }
#
# If labs is empty (default), a single lab is created from customer_email +
# lease_duration above, using the key "default".
# ---------------------------------------------------------------------------

variable "labs" {
  description = "Map of labs to deploy in cohort mode. Key = short lab identifier (used in resource names)."
  type = map(object({
    customer_email = string
    lease_duration = string
    lab_name       = optional(string)
  }))
  default = {}
}
