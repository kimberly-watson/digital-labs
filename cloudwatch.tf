# ---------------------------------------------------------------------------
# CloudWatch Dashboard — Digital Labs Overview
#
# Automatically renders one section per deployed lab, showing:
#   - Welcomer / Notifier / Terminator Lambda invocations + errors
#   - EC2 CPU utilization + network I/O
#   - Nexus and IQ Server container log tails (shared, bottom of page)
#
# Apply to create/update: terraform apply -auto-approve
# ---------------------------------------------------------------------------

locals {
  # Build an ordered list of per-lab data for widget position math.
  # instance_id is an apply-time value; dashboard body will be "known after apply"
  # during plan, but correct after apply.
  lab_list = [for k, v in module.lab : {
    key         = k
    instance_id = v.instance_id
  }]
}

resource "aws_cloudwatch_dashboard" "digital_labs" {
  dashboard_name = "digital-labs-overview"

  dashboard_body = jsonencode({
    widgets = flatten([

      # -----------------------------------------------------------------------
      # Header
      # -----------------------------------------------------------------------
      [{
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# 🔬 Sonatype Digital Labs — Health Dashboard\nPer-lab Lambda lifecycle events, EC2 metrics, and container log tails. Auto-refreshes every minute."
        }
      }],

      # -----------------------------------------------------------------------
      # Per-lab sections (one section = 13 rows)
      # -----------------------------------------------------------------------
      [for idx, lab in local.lab_list : [

        # Lab label
        {
          type   = "text"
          x      = 0
          y      = 2 + idx * 13
          width  = 24
          height = 1
          properties = {
            markdown = "### Lab: `${lab.key}`  |  Instance: `${lab.instance_id}`"
          }
        },

        # Welcomer Lambda — invocations + errors
        {
          type   = "metric"
          x      = 0
          y      = 3 + idx * 13
          width  = 8
          height = 6
          properties = {
            title  = "Welcomer Lambda"
            region = var.aws_region
            view   = "timeSeries"
            metrics = [
              ["AWS/Lambda", "Invocations", "FunctionName", "digital-labs-welcomer-${lab.key}",
                { stat = "Sum", period = 3600, label = "Invocations" }],
              ["AWS/Lambda", "Errors", "FunctionName", "digital-labs-welcomer-${lab.key}",
                { stat = "Sum", period = 3600, color = "#d62728", label = "Errors" }],
            ]
          }
        },

        # Notifier Lambda — invocations + errors
        {
          type   = "metric"
          x      = 8
          y      = 3 + idx * 13
          width  = 8
          height = 6
          properties = {
            title  = "Notifier Lambda"
            region = var.aws_region
            view   = "timeSeries"
            metrics = [
              ["AWS/Lambda", "Invocations", "FunctionName", "digital-labs-notifier-${lab.key}",
                { stat = "Sum", period = 3600, label = "Invocations" }],
              ["AWS/Lambda", "Errors", "FunctionName", "digital-labs-notifier-${lab.key}",
                { stat = "Sum", period = 3600, color = "#d62728", label = "Errors" }],
            ]
          }
        },

        # Terminator Lambda — invocations + errors
        {
          type   = "metric"
          x      = 16
          y      = 3 + idx * 13
          width  = 8
          height = 6
          properties = {
            title  = "Terminator Lambda"
            region = var.aws_region
            view   = "timeSeries"
            metrics = [
              ["AWS/Lambda", "Invocations", "FunctionName", "digital-labs-terminator-${lab.key}",
                { stat = "Sum", period = 3600, label = "Invocations" }],
              ["AWS/Lambda", "Errors", "FunctionName", "digital-labs-terminator-${lab.key}",
                { stat = "Sum", period = 3600, color = "#d62728", label = "Errors" }],
            ]
          }
        },

        # EC2 CPU utilization
        {
          type   = "metric"
          x      = 0
          y      = 9 + idx * 13
          width  = 12
          height = 6
          properties = {
            title  = "EC2 CPU Utilization — ${lab.key}"
            region = var.aws_region
            view   = "timeSeries"
            metrics = [
              ["AWS/EC2", "CPUUtilization", "InstanceId", lab.instance_id,
                { stat = "Average", period = 300, color = "#2ca02c", label = "CPU %" }],
            ]
          }
        },

        # EC2 network in/out
        {
          type   = "metric"
          x      = 12
          y      = 9 + idx * 13
          width  = 12
          height = 6
          properties = {
            title  = "EC2 Network — ${lab.key}"
            region = var.aws_region
            view   = "timeSeries"
            metrics = [
              ["AWS/EC2", "NetworkIn", "InstanceId", lab.instance_id,
                { stat = "Sum", period = 300, label = "In (bytes)" }],
              ["AWS/EC2", "NetworkOut", "InstanceId", lab.instance_id,
                { stat = "Sum", period = 300, color = "#ff7f0e", label = "Out (bytes)" }],
            ]
          }
        },

      ]],

      # -----------------------------------------------------------------------
      # Shared: container log tails (stdout/stderr via Docker awslogs driver)
      # -----------------------------------------------------------------------
      [
        {
          type   = "log"
          x      = 0
          y      = 2 + length(local.lab_list) * 13
          width  = 12
          height = 8
          properties = {
            title   = "Nexus Container Logs (stdout)"
            region  = var.aws_region
            view    = "table"
            query   = "SOURCE '/digital-labs/nexus' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          }
        },
        {
          type   = "log"
          x      = 12
          y      = 2 + length(local.lab_list) * 13
          width  = 12
          height = 8
          properties = {
            title   = "IQ Server Container Logs (stdout)"
            region  = var.aws_region
            view    = "table"
            query   = "SOURCE '/digital-labs/iq-server' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          }
        },
      ],

      # -----------------------------------------------------------------------
      # Shared: structured audit + request logs (via CloudWatch agent)
      # -----------------------------------------------------------------------
      [
        {
          type   = "log"
          x      = 0
          y      = 10 + length(local.lab_list) * 13
          width  = 12
          height = 8
          properties = {
            title   = "Nexus Audit Log"
            region  = var.aws_region
            view    = "table"
            query   = "SOURCE '/digital-labs/nexus-audit' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          }
        },
        {
          type   = "log"
          x      = 12
          y      = 10 + length(local.lab_list) * 13
          width  = 12
          height = 8
          properties = {
            title   = "IQ Server Audit Log"
            region  = var.aws_region
            view    = "table"
            query   = "SOURCE '/digital-labs/iq-audit' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          }
        },
        {
          type   = "log"
          x      = 0
          y      = 18 + length(local.lab_list) * 13
          width  = 12
          height = 8
          properties = {
            title   = "Nexus Request Log"
            region  = var.aws_region
            view    = "table"
            query   = "SOURCE '/digital-labs/nexus-requests' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          }
        },
        {
          type   = "log"
          x      = 12
          y      = 18 + length(local.lab_list) * 13
          width  = 12
          height = 8
          properties = {
            title   = "IQ Server Request Log"
            region  = var.aws_region
            view    = "table"
            query   = "SOURCE '/digital-labs/iq-requests' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          }
        },
      ],

    ])
  })

  depends_on = [module.lab]
}

# ---------------------------------------------------------------------------
# Output: direct link to the dashboard
# ---------------------------------------------------------------------------

output "dashboard_url" {
  description = "CloudWatch dashboard — direct console link"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.digital_labs.dashboard_name}"
}
