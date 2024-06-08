provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "msk_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "msk_vpc"
  }
}

# Subnets
resource "aws_subnet" "msk_subnet" {
  count = 3
  vpc_id = aws_vpc.msk_vpc.id
  cidr_block = cidrsubnet(aws_vpc.msk_vpc.cidr_block, 8, count.index)
  availability_zone = element(["us-east-1a", "us-east-1d", "us-east-1c"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "msk_subnet_${count.index}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.msk_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public_rt"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.msk_vpc.id

  tags = {
    Name = "gw"
  }
}

resource "aws_route_table_association" "a" {
  count          = 3
  subnet_id      = element(aws_subnet.msk_subnet[*].id, count.index)
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for InfluxDB
resource "aws_security_group" "influxdb_sg" {
  vpc_id = aws_vpc.msk_vpc.id

  ingress {
    from_port   = 8086
    to_port     = 8086
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Inbound traffic on port 22 for SSH access
  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "influxdb_sg"
  }
}

# Security Group for Lambda
resource "aws_security_group" "lambda_sg" {
  vpc_id = aws_vpc.msk_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lambda_sg"
  }
}


# Security Group
resource "aws_security_group" "msk_sg" {
  vpc_id = aws_vpc.msk_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "msk_sg"
  }
}

# MSK Cluster
resource "aws_msk_cluster" "example" {
  cluster_name           = "example-cluster"
  kafka_version          = "2.8.1"
  number_of_broker_nodes = 3

  broker_node_group_info {
    # instance_type   = "kafka.m5.large"
    instance_type   = "kafka.t3.small"
    client_subnets  = aws_subnet.msk_subnet[*].id
    security_groups = [aws_security_group.msk_sg.id]
  }

  encryption_info {
    encryption_in_transit {
      # client_broker = "TLS"
      # in_cluster    = true
      client_broker = "PLAINTEXT"
      in_cluster    = false
    }
  }

  tags = {
    Name = "example-cluster"
  }
}

# # Null resource to create Kafka topic if it does not exist
# resource "null_resource" "create_kafka_topic" {
#   provisioner "local-exec" {
#     command = "${path.module}/create_topic.sh ${data.aws_msk_cluster.msk.bootstrap_brokers} home-sensors"
#   }

#   # Make sure this runs only after the MSK cluster is created
#   depends_on = [aws_msk_cluster.example]

#   # Add a trigger to force rerun
#   triggers = {
#     always_run = "${timestamp()}"
#   }
# }

# Data source to fetch MSK broker information
data "aws_msk_cluster" "msk" {
  cluster_name = aws_msk_cluster.example.cluster_name
}

resource "aws_instance" "influxdb" {
  ami           = "ami-04505e74c0741db8d"  # Amazon Linux 2 AMI for us-east-1
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.msk_subnet[0].id
  security_groups = [aws_security_group.influxdb_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "InfluxDB"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              docker run -d -p 8086:8086 --name=influxdb \
                -e DOCKER_INFLUXDB_INIT_MODE=setup \
                -e DOCKER_INFLUXDB_INIT_USERNAME=my-user \
                -e DOCKER_INFLUXDB_INIT_PASSWORD=my-password \
                -e DOCKER_INFLUXDB_INIT_ORG=my-org \
                -e DOCKER_INFLUXDB_INIT_BUCKET=my-bucket \
                -e DOCKER_INFLUXDB_INIT_RETENTION=1w \
                influxdb:2.0
            EOF

  # lifecycle {
  #   prevent_destroy = true
  # }
}




# EC2 instance for Grafana
resource "aws_instance" "grafana" {
  ami           = "ami-04505e74c0741db8d"  # Amazon Linux 2 AMI for us-east-1
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.msk_subnet[1].id
  security_groups = [aws_security_group.msk_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "Grafana"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              docker run -d -p 3000:3000 --name=grafana grafana/grafana
            EOF
  
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_msk_influxdb_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_msk_influxdb_policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "kafka:DescribeCluster",
          "kafka:GetBootstrapBrokers",
          "kafka:ListNodes",
          "kafka:DescribeNode",
          "kafka:ListTopics",
          "kafka:DescribeTopic",
          "kafka:ReadData",
          "kafka:CreateTopic"
        ],
        Effect = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Function to Create Kafka Topic
resource "aws_lambda_function" "create_kafka_topic" {
  filename         = "lambda_create_topic.zip"
  function_name    = "CreateKafkaTopicFunction"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_create_topic.lambda_handler"
  runtime          = "python3.8"
  timeout          = 60
  memory_size      = 128
  environment {
    variables = {
      KAFKA_BROKER = data.aws_msk_cluster.msk.bootstrap_brokers
    }
  }
  vpc_config {
    subnet_ids         = aws_subnet.msk_subnet[*].id
    security_group_ids = [aws_security_group.msk_sg.id]
  }

  source_code_hash = filebase64sha256("lambda_create_topic.zip")
}

# Lambda Function to Send Data to Kafka
resource "aws_lambda_function" "kafka_producer" {
  filename         = "lambda_producer_function.zip"
  function_name    = "KafkaProducerFunction"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_producer.lambda_handler"
  runtime          = "python3.8"
  timeout          = 200
  memory_size      = 128
  environment {
    variables = {
      KAFKA_BROKER = data.aws_msk_cluster.msk.bootstrap_brokers
      KAFKA_TOPIC  = "home-sensors"
    }
  }
  vpc_config {
    subnet_ids         = aws_subnet.msk_subnet[*].id
    security_group_ids = [aws_security_group.msk_sg.id]
  }

  source_code_hash = filebase64sha256("lambda_producer_function.zip")
}

# Lambda Function to Consume Kafka and Write to InfluxDB
resource "aws_lambda_function" "kafka_consumer" {
  filename         = "target/lambda-kafka-influxdb-1.0-SNAPSHOT.jar"
  function_name    = "KafkaConsumerFunction"
  role             = aws_iam_role.lambda_role.arn
  handler          = "com.example.LambdaKafkaInfluxDBHandler::handleRequest"
  runtime          = "java11"
  timeout          = 200
  memory_size      = 512
  environment {
    variables = {
      KAFKA_BROKER      = data.aws_msk_cluster.msk.bootstrap_brokers
      KAFKA_TOPIC       = "home-sensors"
      INFLUXDB_ADDRESS  = aws_instance.influxdb.public_ip
      # INFLUXDB_URL      = "http://${aws_instance.influxdb.public_ip}:8086"
      INFLUXDB_URL      = "http://${aws_instance.influxdb.private_ip}:8086"
      INFLUXDB_PORT     = "8086"
      INFLUXDB_USER     = "my-user"
      INFLUXDB_PASSWORD = "my-password"
      INFLUXDB_BUCKET   = "my-bucket"
      INFLUXDB_TOKEN    = "your-influxdb-token"
      INFLUXDB_ORG      = "my-org"
    }
  }
  vpc_config {
    subnet_ids         = aws_subnet.msk_subnet[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  source_code_hash = filebase64sha256("target/lambda-kafka-influxdb-1.0-SNAPSHOT.jar")
}

# CloudWatch Event to trigger the consumer Lambda function every 5 minutes
resource "aws_cloudwatch_event_rule" "consume_kafka_topic" {
  name                = "consume-kafka-topic"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "consume_kafka_topic_target" {
  rule      = aws_cloudwatch_event_rule.consume_kafka_topic.name
  target_id = "KafkaConsumerFunction"
  arn       = aws_lambda_function.kafka_consumer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_invoke_consumer" {
  statement_id  = "AllowCloudWatchToInvokeConsumer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kafka_consumer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.consume_kafka_topic.arn
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "KafkaProducerAPI"
  description = "API to send data to Kafka through Lambda"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "send"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.kafka_producer.invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kafka_producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  depends_on = [aws_api_gateway_integration.integration]
}

output "api_endpoint" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}/send"
}

# Debug Outputs
output "debug_influxdb" {
  value = aws_instance.influxdb.public_ip
}

output "debug_grafana" {
  value = aws_instance.grafana.public_ip
}

output "debug_msk" {
  value = aws_msk_cluster.example.arn
}

# Outputs
output "vpc_id" {
  value = aws_vpc.msk_vpc.id
}

output "msk_cluster_arn" {
  value = aws_msk_cluster.example.arn
}

output "influxdb_public_ip" {
  value = aws_instance.influxdb.public_ip
}

output "grafana_public_ip" {
  value = aws_instance.grafana.public_ip
}

output "msk_bootstrap_brokers" {
  value = data.aws_msk_cluster.msk.bootstrap_brokers
}
