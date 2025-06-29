#creating EC2 instance

data "aws_ami" "test_instance_nisha" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "test_instance_resource_nisha" {
  ami           = data.aws_ami.test_instance_nisha.id
  instance_type = "t2.micro"

  tags = {
    Name = "test_ec2_instance_nisha"
  }
}

#Creating VPC

resource "aws_vpc" "nisha_test_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "nisha_test_vpc"
  }
}

# Subnet 1
resource "aws_subnet" "nisha_test_subnet" {
  vpc_id                  = aws_vpc.nisha_test_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "nisha_test_subnet"
  }
}

# Subnet 2
resource "aws_subnet" "nisha_test_subnet_b" {
  vpc_id                  = aws_vpc.nisha_test_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "nisha_test_subnet_b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "nisha_test_gw" {
  vpc_id = aws_vpc.nisha_test_vpc.id
  tags = {
    Name = "nisha_test_ig"
  }
}

# Route Table
resource "aws_route_table" "aws_route_table_nisha" {
  vpc_id = aws_vpc.nisha_test_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nisha_test_gw.id
  }
  tags = {
    Name = "aws_route_table_nisha"
  }
}

resource "aws_route_table_association" "aws_route_table_association_nisha" {
  subnet_id      = aws_subnet.nisha_test_subnet.id
  route_table_id = aws_route_table.aws_route_table_nisha.id
}

# Security Group
resource "aws_security_group" "nisha_test_ag" {
  vpc_id = aws_vpc.nisha_test_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "nisha_test_ag"
  }
}

# Application Load Balancer
resource "aws_lb" "nisha_test_alb" {
  name               = "nisha-test-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nisha_test_ag.id]
  subnets            = [
        aws_subnet.nisha_test_subnet.id,
        aws_subnet.nisha_test_subnet_b.id
    ]
}


# Target Group
resource "aws_lb_target_group" "nisha_test_tg" {
  name     = "nisha-test-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.nisha_test_vpc.id
}

# Listener
resource "aws_lb_listener" "nisha_test_listener" {
  load_balancer_arn = aws_lb.nisha_test_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nisha_test_tg.arn
  }
  tags = {
    Name = "nisha_test_listener"
  }
}

# Launch Template for ASG
resource "aws_launch_template" "nisha_test_lt" {
  name_prefix   = "nisha-lt-test"
  image_id      = data.aws_ami.test_instance_nisha.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.nisha_test_ag.id]
}

# Auto Scaling Group
resource "aws_autoscaling_group" "nisha_test_asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.nisha_test_subnet.id]
  launch_template {
    id      = aws_launch_template.nisha_test_lt.id
    version = "$Latest"
  }
  target_group_arns    = [aws_lb_target_group.nisha_test_tg.arn]
  health_check_type    = "EC2"
  tag {
    key                 = "Name"
    value               = "nisha-asg-instance"
    propagate_at_launch = true
  }
}

# SQS creation
resource "aws_sqs_queue" "terraform_queue_nisha" {
  name = "terraform-example-queue-nisha"
}

# SNS creation
resource "aws_sns_topic" "nisha_test_topic" {
  name = "nisha-test-topic"
}

# Connect SQS with Lambda
# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role_nisha"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM role for SQS
resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "lambda_sqs_policy_name"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.terraform_queue_nisha.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.lambda_dlq_nisha.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.nisha_stream.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
data "archive_file" "python_code_deployment_architecture_nisha" {
  type        = "zip"
  source_file = "${path.module}/lambda/rpsRush.py"
  output_path = "${path.module}/lambda/function.zip"
}
resource "aws_lambda_function" "nisha_lambda" {
  filename         = data.archive_file.python_code_deployment_architecture_nisha.output_path
  function_name    = "lambda_function_nisha" 
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "rpsRush.lambda_handler"
  source_code_hash = data.archive_file.python_code_deployment_architecture_nisha.output_base64sha256
  runtime = "python3.12"

  # Add DLQ config to Lambda function
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq_nisha.arn
  }
}

# Event Source Mapping: Connect SQS to Lambda
resource "aws_lambda_event_source_mapping" "sqs_to_lambda_nisha" {
  event_source_arn = aws_sqs_queue.terraform_queue_nisha.arn
  function_name    = aws_lambda_function.nisha_lambda.arn
  batch_size       = 1
  enabled          = true
}

#Connect SNS with Lambda
# SNS Subscription for Lambda
resource "aws_sns_topic_subscription" "sns_lambda_nisha" {
  topic_arn = aws_sns_topic.nisha_test_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.nisha_lambda.arn
}

# Allow SNS to invoke Lambda
resource "aws_lambda_permission" "allow_sns_invoke_nisha" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nisha_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.nisha_test_topic.arn
}

# Connect lambda with dead letter queue
# Create a Dead Letter Queue (SQS)
resource "aws_sqs_queue" "lambda_dlq_nisha" {
  name = "lambda-dlq-nisha"
}

# Connect lambda with Kinesis. 
resource "aws_kinesis_stream" "nisha_stream" {
  name             = "nisha-kinesis-stream"
  shard_count      = 1
  retention_period = 24
}

resource "aws_lambda_event_source_mapping" "kinesis_to_lambda_nisha" {
  event_source_arn  = aws_kinesis_stream.nisha_stream.arn
  function_name     = aws_lambda_function.nisha_lambda.arn
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true
}

# Configuring eks
# Create EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRoleNisha"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Create EKS Node Group IAM Role
resource "aws_iam_role" "eks_node_group_role" {
  name = "eksNodeGroupRoleNisha"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Create EKS Cluster
resource "aws_eks_cluster" "nisha_eks" {
  name     = "nisha-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.nisha_test_subnet.id,
      aws_subnet.nisha_test_subnet_b.id
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy
  ]
}

# Create EKS Node Group
resource "aws_eks_node_group" "nisha_eks_nodes" {
  cluster_name    = aws_eks_cluster.nisha_eks.name
  node_group_name = "nisha-eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = [
    aws_subnet.nisha_test_subnet.id,
    aws_subnet.nisha_test_subnet_b.id
  ]
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy
  ]
}