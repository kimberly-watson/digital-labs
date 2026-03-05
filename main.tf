terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "lab_ssm_role" {
  name = "digital-labs-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.lab_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "parameter_store_read" {
  name = "digital-labs-parameter-store-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:us-east-1:*:parameter/digital-labs/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "parameter_store_policy" {
  role       = aws_iam_role.lab_ssm_role.name
  policy_arn = aws_iam_policy.parameter_store_read.arn
}

resource "aws_iam_instance_profile" "lab_profile" {
  name = "digital-labs-instance-profile"
  role = aws_iam_role.lab_ssm_role.name
}

resource "aws_security_group" "lab_sg" {
  name        = "digital-labs-sg"
  description = "Allow Nexus UI and outbound traffic"

  ingress {
    description = "Nexus UI"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "IQ Server / Lifecycle / Firewall UI"
    from_port   = 8070
    to_port     = 8070
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "lab" {
  ami                    = "ami-0f3caa1cf4417e51b"
  instance_type          = "t3.large"
  iam_instance_profile   = aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.lab_sg.id]
  user_data              = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "sonatype-lab"
  }
}

output "instance_id" {
  value = aws_instance.lab.id
}

output "public_ip" {
  value = aws_instance.lab.public_ip
}
