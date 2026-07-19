# -----------------------------------------------
# Phase 2 — compute API
# Skyfield Lambda layer + API Lambda + API Gateway HTTP API (5 routes)
# -----------------------------------------------

# -----------------------------------------------
# Skyfield layer — layers/skyfield/python/ must be built first by
# layers/skyfield/build.sh (pip cross-compile targeting python3.12/x86_64);
# tofu only zips and publishes it
# -----------------------------------------------

data "archive_file" "skyfield_layer" {
  type        = "zip"
  source_dir  = "${path.module}/../layers/skyfield"
  output_path = "${path.module}/build/skyfield_layer.zip"
  excludes    = ["build.sh", "requirements.txt"]
}

resource "aws_lambda_layer_version" "skyfield" {
  layer_name               = "sattrack-skyfield"
  filename                 = data.archive_file.skyfield_layer.output_path
  source_code_hash         = data.archive_file.skyfield_layer.output_base64sha256
  compatible_runtimes      = ["python3.12"]
  compatible_architectures = ["x86_64"]
}

# -----------------------------------------------
# IAM — API Lambda execution role (read-only on the table)
# -----------------------------------------------

resource "aws_iam_role" "api" {
  name = "sattrack-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_logs" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api" {
  name = "sattrack-api-access"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:Scan"]
      Resource = aws_dynamodb_table.sattrack.arn
    }]
  })
}

# -----------------------------------------------
# Lambda — sattrack-api
# 512 MB: numpy/skyfield import needs the CPU that comes with the memory,
# keeping cold starts tolerable
# -----------------------------------------------

data "archive_file" "api" {
  type        = "zip"
  source_file = "${path.module}/../lambdas/api/handler.py"
  output_path = "${path.module}/build/api.zip"
}

resource "aws_lambda_function" "api" {
  function_name    = "sattrack-api"
  role             = aws_iam_role.api.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  timeout          = 15
  memory_size      = 512
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  layers           = [aws_lambda_layer_version.skyfield.arn]

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.sattrack.name
      HOME_LAT   = "26.13"
      HOME_LON   = "-80.23"
    }
  }

  tags = {
    Name = "sattrack-api"
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = 14
}

# -----------------------------------------------
# API Gateway HTTP API — 5 GET routes, one Lambda proxy integration,
# $default stage with auto-deploy. CORS is wide open for now; tighten
# allow_origins to the CloudFront domain in Phase 3.
# -----------------------------------------------

resource "aws_apigatewayv2_api" "sattrack" {
  name          = "sattrack-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.sattrack.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api" {
  for_each = toset([
    "GET /satellites",
    "GET /satellites/{id}",
    "GET /positions",
    "GET /satellites/{id}/passes",
    "GET /satellites/{id}/tle",
  ])

  api_id    = aws_apigatewayv2_api.sattrack.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.sattrack.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.sattrack.execution_arn}/*/*"
}
