output "instance_id" {
  value = aws_instance.lab.id
}

output "public_ip" {
  value = aws_instance.lab.public_ip
}

output "lab_url" {
  value = "http://${aws_instance.lab.public_ip}"
}

output "nexus_url" {
  value = "http://${aws_instance.lab.public_ip}:8081"
}

output "iq_url" {
  value = "http://${aws_instance.lab.public_ip}:8070"
}

output "terminates_at" {
  value = local.termination_time
}
