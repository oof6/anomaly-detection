provider "aws" {
    region = "us-east-1"
}

# -------------------------------------------------------------------------------

# S3 Bucket 
resource "aws_s3_bucket" "app_bucket" {
    bucket_prefix = "anomaly-detection-"
    force_destroy = true
}

# -------------------------------------------------------------------------------

# SNS Topic
resource "aws_sns_topic" "app_sns" {
    name = "ds5220-dp1"
}

# -------------------------------------------------------------------------------

# SNS Topic Policy 
resource "aws_sns_topic_policy" "default" {
    arn = aws_sns_topic.app_sns.arn
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.app_sns.arn
        Condition = {
            ArnLike = { "aws:SourceArn" = aws_s3_bucket.app_bucket.arn }
        }
        }]
    })
}

# -------------------------------------------------------------------------------

# S3 Event Notification 
resource "aws_s3_bucket_notification" "bucket_notification" {
    bucket = aws_s3_bucket.app_bucket.id
    topic {
        topic_arn     = aws_sns_topic.app_sns.arn
        events        = ["s3:ObjectCreated:*"]
        filter_prefix = "raw/"
        filter_suffix = ".csv"
    }

    depends_on = [aws_sns_topic_policy.default]
}

# -------------------------------------------------------------------------------

# Elastic IP 
resource "aws_eip" "app_eip" {
    instance = aws_instance.app_server.id
    domain   = "vpc"
}

# -------------------------------------------------------------------------------

# SNS Subscription
resource "aws_sns_topic_subscription" "app_http_target" {
    topic_arn = aws_sns_topic.app_sns.arn
    protocol  = "http"
    endpoint  = "http://${aws_eip.app_eip.public_ip}:8000/notify"
}

# -------------------------------------------------------------------------------

# IAM Role & Instance Profile
resource "aws_iam_role" "ec2_role" {
    name = "EC2AppS3Role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        }]
    })
}

resource "aws_iam_role_policy" "s3_access" {
    name = "S3Access"
    role = aws_iam_role.ec2_role.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.app_bucket.arn, "${aws_s3_bucket.app_bucket.arn}/*"]
        }]
    })
}

resource "aws_iam_instance_profile" "app_profile" {
    name = "AppInstanceProfile"
    role = aws_iam_role.ec2_role.name
}

# ----------------------------------------------------------------------------

# EC2 Instance 
resource "aws_instance" "app_server" {
    ami           = "ami-04b70fa74e45c3917" # Ubuntu 24.04 
    instance_type = "t3.micro"
    iam_instance_profile = aws_iam_instance_profile.app_profile.name
    vpc_security_group_ids = [aws_security_group.app_sg.id]

    root_block_device {
        volume_size = 16 
    }

    user_data = <<-EOF
                #!/bin/bash
                apt-get update
                apt-get install -y python3-pip python3-venv git
                echo "BUCKET_NAME='${aws_s3_bucket.app_bucket.id}'" >> /etc/environment
                export BUCKET_NAME='${aws_s3_bucket.app_bucket.id}'
                
                # Clone repository and setup env
                cd /home/ubuntu
                git clone https://github.com/oof6/anomaly-detection.git app
                cd app

                # create virtual environment
                python3 -m venv venv
                source venv/bin/activate


                
                # install requirements
                pip install -r requirements.txt
                pip install fastapi uvicorn

                # run the application
                mkdir -p logs
                chown -R ubuntu:ubuntu /home/ubuntu/app
                sudo -u ubuntu BUCKET_NAME='${aws_s3_bucket.app_bucket.id}' bash -c "source /home/ubuntu/app/venv/bin/activate && fastapi run app.py --port 8000" &

                EOF

    depends_on = [aws_sns_topic_policy.default]

}

# ----------------------------------------------------------------------------

# Security Group 
resource "aws_security_group" "app_sg" {
    name = "app_sg"
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["67.129.8.198/32"] # my IP
    }
    ingress {
        from_port   = 8000
        to_port     = 8000
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

# ----------------------------------------------------------------------------

# Output 
output "instance_ip" {
    description = "Elastic IP address of the instance"
    value = aws_eip.app_eip.public_ip
}

output "bucket_name" {
    description = "S3 bucket name"
    value = aws_s3_bucket.app_bucket.id
}

output "sns_topic_arn" {
    description = "ARN of the SNS topic"
    value = aws_sns_topic.app_sns.arn
}