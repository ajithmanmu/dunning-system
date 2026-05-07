resource "aws_api_gateway_rest_api" "dunning" {
  name = "${var.project_name}-api"
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.dunning.id
  parent_id   = aws_api_gateway_rest_api.dunning.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.dunning.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook" {
  rest_api_id             = aws_api_gateway_rest_api.dunning.id
  resource_id             = aws_api_gateway_resource.webhook.id
  http_method             = aws_api_gateway_method.webhook_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook_handler.invoke_arn
}

resource "aws_api_gateway_deployment" "dunning" {
  rest_api_id = aws_api_gateway_rest_api.dunning.id

  depends_on = [
    aws_api_gateway_integration.webhook
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.dunning.id
  deployment_id = aws_api_gateway_deployment.dunning.id
  stage_name    = "prod"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.dunning.execution_arn}/*/*"
}

output "webhook_url" {
  value       = "${aws_api_gateway_stage.prod.invoke_url}/webhook"
  description = "Stripe webhook endpoint — add this to Stripe Dashboard and stripe listen"
}
