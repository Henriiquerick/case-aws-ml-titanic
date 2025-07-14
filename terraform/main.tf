# Configura o provedor AWS
provider "aws" {
  region = "sa-east-1" # Define a região padrão para todos os recursos
}

# --- API Gateway: REST API (O "Portão" Principal) ---
resource "aws_api_gateway_rest_api" "titanic_api" {
  name        = "TitanicSurvivorsAPI"
  description = "API para prever sobreviventes do Titanic"

  endpoint_configuration {
    types = ["EDGE"]
  }

  tags = {
    Project = "TitanicCase"
    Environment = "Dev"
  }
}

# --- API Gateway: Recurso /sobreviventes ---
resource "aws_api_gateway_resource" "sobreviventes_resource" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  parent_id   = aws_api_gateway_rest_api.titanic_api.root_resource_id
  path_part   = "sobreviventes"
}

# --- API Gateway: Recurso /sobreviventes/{id} (para operações com ID específico) ---
resource "aws_api_gateway_resource" "sobreviventes_id_resource" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  parent_id   = aws_api_gateway_resource.sobreviventes_resource.id
  path_part   = "{id}"
}

# --- IAM Role para o API Gateway enviar logs para o CloudWatch ---
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "APIGatewayCloudWatchLogsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# Anexa a política de permissão para escrever logs no CloudWatch à Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# --- Adiciona a configuração de logs da conta API Gateway ---
# Essa configuração é global para a conta AWS na região, não específica da API
resource "aws_api_gateway_account" "api_gateway_account_settings" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn

  # Depende do IAM Role e da Política de Anexo estarem prontos
  depends_on = [
    aws_iam_role_policy_attachment.api_gateway_cloudwatch_policy
  ]
}

# --- AWS Lambda: Permissões (Role) para a Função Lambda ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "titanic-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "TitanicCase"
    Environment = "Dev"
  }
}

# Anexa políticas de permissão à Role da Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" # Permite logs no CloudWatch
}

# Se você for habilitar o DynamoDB no futuro, essa permissão será necessária
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" # Acesso total ao DynamoDB para o case (em prod, seria mais restrito)
}

# --- AWS Lambda: Função Lambda em si ---
resource "aws_lambda_function" "titanic_survivors_lambda" {
  function_name    = "TitanicSurvivorsLambda"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8" # Manter python3.8
  role             = aws_iam_role.lambda_exec_role.arn

  # Código da Lambda via S3
  s3_bucket        = aws_s3_bucket.lambda_code_bucket.id # O bucket S3 que acabamos de criar
  s3_key           = "lambda_function.zip" # O nome do arquivo ZIP dentro do bucket

  # Remova as linhas 'filename' e 'source_code_hash' se existirem aqui!
  # filename         = "../lambda/lambda_function.zip" 
  # source_code_hash = filebase64sha256("../lambda/lambda_function.zip") 

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = "TitanicSurvivors"
    }
  }

  timeout     = 30
  memory_size = 256

  tags = {
    Project     = "TitanicCase"
    Environment = "Dev"
    manual_deploy_trigger = "v10" # Mude para um NOVO valor (ex: "v10")
  }
}

# --- Permissão para o API Gateway invocar a Lambda ---
resource "aws_lambda_permission" "apigw_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.titanic_survivors_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.titanic_api.execution_arn}/*/*"
}

# --- AWS DynamoDB: Tabela para Armazenar Dados de Sobreviventes ---
/*
resource "aws_dynamodb_table" "titanic_survivors_table" {
  name           = "TitanicSurvivors"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PassengerId"

  attribute {
    name = "PassengerId"
    type = "S"
  }

  tags = {
    Project = "TitanicCase"
    Environment = "Dev"
  }
}
*/

# --- API Gateway: Métodos HTTP (sem respostas explícitas de método/integração) ---

# Método POST para /sobreviventes
resource "aws_api_gateway_method" "post_sobreviventes" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integração POST para /sobreviventes (Lambda)
resource "aws_api_gateway_integration" "post_sobreviventes_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_resource.id
  http_method             = aws_api_gateway_method.post_sobreviventes.http_method
  type                    = "AWS_PROXY"

  integration_http_method = "POST"
  uri                     = aws_lambda_function.titanic_survivors_lambda.invoke_arn
}

# Método GET para /sobreviventes
resource "aws_api_gateway_method" "get_sobreviventes" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integração GET para /sobreviventes (Lambda)
resource "aws_api_gateway_integration" "get_sobreviventes_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_resource.id
  http_method             = aws_api_gateway_method.get_sobreviventes.http_method
  type                    = "AWS_PROXY"

  integration_http_method = "POST"
  uri                     = aws_lambda_function.titanic_survivors_lambda.invoke_arn
}

# Método GET para /sobreviventes/{id}
resource "aws_api_gateway_method" "get_sobreviventes_id" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integração GET /{id} para /sobreviventes (Lambda)
resource "aws_api_gateway_integration" "get_sobreviventes_id_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method             = aws_api_gateway_method.get_sobreviventes_id.http_method
  type                    = "AWS_PROXY"

  integration_http_method = "POST"
  uri                     = aws_lambda_function.titanic_survivors_lambda.invoke_arn
}

# Método DELETE para /sobreviventes/{id}
resource "aws_api_gateway_method" "delete_sobreviventes_id" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method   = "DELETE"
  authorization = "NONE"
}

# Integração DELETE /{id} para /sobreviventes (Lambda)
resource "aws_api_gateway_integration" "delete_sobreviventes_id_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method             = aws_api_gateway_method.delete_sobreviventes_id.http_method
  type                    = "AWS_PROXY"

  integration_http_method = "POST"
  uri                     = aws_lambda_function.titanic_survivors_lambda.invoke_arn
}

# --- API Gateway: Implantação (Deployment) da API ---
resource "aws_api_gateway_deployment" "titanic_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id

  depends_on = [
    aws_api_gateway_method.post_sobreviventes,
    aws_api_gateway_method.get_sobreviventes,
    aws_api_gateway_method.get_sobreviventes_id,
    aws_api_gateway_method.delete_sobreviventes_id,
    aws_api_gateway_integration.post_sobreviventes_integration,
    aws_api_gateway_integration.get_sobreviventes_integration,
    aws_api_gateway_integration.get_sobreviventes_id_integration,
    aws_api_gateway_integration.delete_sobreviventes_id_integration,
    aws_lambda_function.titanic_survivors_lambda
  ]

  lifecycle {
    create_before_destroy = true
    replace_triggered_by = [
      aws_lambda_function.titanic_survivors_lambda.last_modified
    ]
  }

  triggers = {
    api_method_integration_hash = sha1(jsonencode([
      aws_api_gateway_rest_api.titanic_api.body,
      aws_lambda_function.titanic_survivors_lambda.last_modified,
      aws_api_gateway_method.post_sobreviventes.id,
      aws_api_gateway_method.get_sobreviventes.id,
      aws_api_gateway_method.get_sobreviventes_id.id,
      aws_api_gateway_method.delete_sobreviventes_id.id,
      aws_api_gateway_integration.post_sobreviventes_integration.id,
      aws_api_gateway_integration.get_sobreviventes_integration.id,
      aws_api_gateway_integration.get_sobreviventes_id_integration.id,
      aws_api_gateway_integration.delete_sobreviventes_id_integration.id
    ]))
    manual_deploy_trigger = "v4" # Mude para um NOVO valor para forçar o deploy (ex: "v5")
  }
}

# --- CloudWatch Log Group para os Logs de Acesso do API Gateway ---
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.titanic_api.name}/dev"
  retention_in_days = 7
}

# --- API Gateway: Estágio (Stage) da Implantação ---
resource "aws_api_gateway_stage" "titanic_api_stage" {
  deployment_id = aws_api_gateway_deployment.titanic_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  stage_name    = "dev"

  # Adiciona dependência explícita para a configuração de conta do API Gateway
  depends_on = [
    aws_api_gateway_account.api_gateway_account_settings
  ]

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  cache_cluster_enabled = false
  cache_cluster_size    = "0.5"
}

# --- S3 Bucket para Código da Lambda ---
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

resource "aws_s3_bucket" "lambda_code_bucket" {
  bucket = "titanic-lambda-code-${random_string.bucket_suffix.result}" # Nome único para o bucket
  # acl    = "private" # 'acl' é depreciado, usar 'ownership_controls' e 'bucket_policy'
  
  # Boas práticas para S3
  force_destroy = true # Permite deletar o bucket mesmo com objetos dentro (CUIDADO em produção)

  tags = {
    Project = "TitanicCase"
    Environment = "Dev"
  }
}

# --- Permissão para a Role da Lambda ler do S3 ---
resource "aws_iam_role_policy_attachment" "lambda_s3_read_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Permissão para ler S3
}