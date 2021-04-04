data "aws_region" "region" {}

resource "aws_default_vpc" "default" {}

data "aws_subnet_ids" "default" {
  vpc_id = aws_default_vpc.default.id
}

resource "aws_vpc" "visit" {
  cidr_block = var.visit_cidr
  tags = {
    Name = "${var.prefix}-visit"
  }
}

resource "aws_subnet" "visit" {
  vpc_id     = aws_vpc.visit.id
  cidr_block = aws_vpc.visit.cidr_block
  tags = {
    Name = "${var.prefix}-visit"
  }
}

resource "aws_internet_gateway" "visit" {
  vpc_id = aws_vpc.visit.id
  tags = {
    Name = "${var.prefix}-visit"
  }
}

resource "aws_default_route_table" "visit" {
  default_route_table_id = aws_vpc.visit.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.visit.id
  }
}

resource "aws_security_group" "visit" {
  name   = "${var.prefix}-visit"
  vpc_id = aws_vpc.visit.id
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
  }
}

resource "aws_sqs_queue" "queue" {
  name                       = var.prefix
  visibility_timeout_seconds = 80
  message_retention_seconds  = 3600
}

resource "aws_ecs_cluster" "visit" {
  name = "${var.prefix}-visit"
}

data "aws_iam_policy_document" "visit_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "visit_execution" {
  name                = "${var.prefix}-visit-execution"
  assume_role_policy  = data.aws_iam_policy_document.visit_assume.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
}

data "aws_iam_policy_document" "visit_task" {
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage"]
    resources = [aws_sqs_queue.queue.arn]
  }
}

resource "aws_iam_role" "visit_task" {
  name               = "${var.prefix}-visit-task"
  assume_role_policy = data.aws_iam_policy_document.visit_assume.json
  inline_policy {
    name   = "visit"
    policy = data.aws_iam_policy_document.visit_task.json
  }
}

resource "aws_ecs_task_definition" "visit" {
  family                   = "${var.prefix}-visit"
  task_role_arn            = aws_iam_role.visit_task.arn
  execution_role_arn       = aws_iam_role.visit_execution.arn
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions = jsonencode([{
    name      = "visit"
    image     = var.image
    command   = ["visit"]
    essential = true
    image     = var.image
    environment = [{
      name  = "APP_SQS_URL"
      value = aws_sqs_queue.queue.id
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.visit.name
        awslogs-region        = data.aws_region.region.name
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "visit" {
  name                               = "visit"
  cluster                            = aws_ecs_cluster.visit.arn
  desired_count                      = var.visit_scale
  deployment_minimum_healthy_percent = 100
  launch_type                        = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.visit.id]
    security_groups  = [aws_security_group.visit.id]
    assign_public_ip = true
  }
  task_definition = aws_ecs_task_definition.visit.arn
  depends_on      = [aws_default_route_table.visit]
}

resource "aws_cloudwatch_log_group" "submit" {
  name = "/aws/lambda/${var.prefix}-submit"
}

resource "aws_cloudwatch_log_group" "visit" {
  name = "/ecs/${var.prefix}-visit"
}

data "aws_iam_policy_document" "submit_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "submit_task" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.queue.arn]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.submit.arn}:*"]
  }
}

resource "aws_iam_role" "submit" {
  name               = "${var.prefix}-submit"
  assume_role_policy = data.aws_iam_policy_document.submit_assume.json
  inline_policy {
    name   = "submit"
    policy = data.aws_iam_policy_document.submit_task.json
  }
}

resource "aws_lambda_function" "submit" {
  function_name = "${var.prefix}-submit"
  role          = aws_iam_role.submit.arn
  package_type  = "Image"
  image_config {
    command = ["submit"]
  }
  image_uri                      = var.image
  reserved_concurrent_executions = var.submit_max_scale
  environment {
    variables = {
      APP_SQS_URL          = aws_sqs_queue.queue.id
      APP_RECAPTCHA_SITE   = var.recaptcha.site
      APP_RECAPTCHA_SECRET = var.recaptcha.secret
    }
  }
}

resource "aws_security_group" "submit" {
  name   = "${var.prefix}-submit"
  vpc_id = aws_default_vpc.default.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
  }
}

resource "aws_lb" "submit" {
  name            = "${var.prefix}-submit"
  subnets         = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.submit.id]
}

resource "aws_lb_target_group" "submit" {
  name        = "${var.prefix}-submit"
  target_type = "lambda"
}

resource "aws_lb_listener" "submit" {
  load_balancer_arn = aws_lb.submit.arn
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.submit.arn
  }
}

resource "aws_lambda_permission" "submit" {
  statement_id  = "${var.prefix}-submit"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.submit.arn
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.submit.arn
}

resource "aws_lb_target_group_attachment" "submit" {
  target_group_arn = aws_lb_target_group.submit.arn
  target_id        = aws_lambda_function.submit.arn
  depends_on       = [aws_lambda_permission.submit]
}
