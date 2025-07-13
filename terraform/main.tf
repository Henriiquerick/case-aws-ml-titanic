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

# --- API Gateway: Método POST para /sobreviventes ---
resource "aws_api_gateway_method" "post_sobreviventes" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_resource.id
  http_method   = "POST"
  authorization = "NONE" # Nenhuma autorização por enquanto (para simplicidade do case)
}

# Integração MOCK para o POST /sobreviventes (resposta temporária)
resource "aws_api_gateway_integration" "post_sobreviventes_mock_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_resource.id
  http_method             = aws_api_gateway_method.post_sobreviventes.http_method
  type                    = "MOCK" # Tipo de integração MOCK
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }" # Retorna um status 200 para qualquer JSON
  }
}

resource "aws_api_gateway_method_response" "post_sobreviventes_200" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_resource.id
  http_method = aws_api_gateway_method.post_sobreviventes.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "post_sobreviventes_mock_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_resource.id
  http_method = aws_api_gateway_method.post_sobreviventes.http_method
  status_code = aws_api_gateway_method_response.post_sobreviventes_200.status_code
  selection_pattern = "" # Padrão vazio para capturar todas as respostas bem-sucedidas
  response_templates = {
    "application/json" = "{ \"message\": \"POST /sobreviventes mock response. Implementar logica ML aqui.\" }"
  }
}

# --- API Gateway: Método GET para /sobreviventes ---
resource "aws_api_gateway_method" "get_sobreviventes" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integração MOCK para o GET /sobreviventes
resource "aws_api_gateway_integration" "get_sobreviventes_mock_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_resource.id
  http_method             = aws_api_gateway_method.get_sobreviventes.http_method
  type                    = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "get_sobreviventes_200" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_resource.id
  http_method = aws_api_gateway_method.get_sobreviventes.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "get_sobreviventes_mock_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_resource.id
  http_method = aws_api_gateway_method.get_sobreviventes.http_method
  status_code = aws_api_gateway_method_response.get_sobreviventes_200.status_code
  selection_pattern = ""
  response_templates = {
    "application/json" = "{ \"message\": \"GET /sobreviventes mock response. Retornar lista aqui.\" }"
  }
}

# --- API Gateway: Método GET para /sobreviventes/{id} ---
resource "aws_api_gateway_method" "get_sobreviventes_id" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integração MOCK para o GET /sobreviventes/{id}
resource "aws_api_gateway_integration" "get_sobreviventes_id_mock_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method             = aws_api_gateway_method.get_sobreviventes_id.http_method
  type                    = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "get_sobreviventes_id_200" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method = aws_api_gateway_method.get_sobreviventes_id.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "get_sobreviventes_id_mock_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method = aws_api_gateway_method.get_sobreviventes_id.http_method
  status_code = aws_api_gateway_method_response.get_sobreviventes_id_200.status_code
  selection_pattern = ""
  response_templates = {
    "application/json" = "{ \"message\": \"GET /sobreviventes/{id} mock response. Retornar detalhes aqui.\" }"
  }
}

# --- API Gateway: Método DELETE para /sobreviventes/{id} ---
resource "aws_api_gateway_method" "delete_sobreviventes_id" {
  rest_api_id   = aws_api_gateway_rest_api.titanic_api.id
  resource_id   = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method   = "DELETE"
  authorization = "NONE"
}

# Integração MOCK para o DELETE /sobreviventes/{id}
resource "aws_api_gateway_integration" "delete_sobreviventes_id_mock_integration" {
  rest_api_id             = aws_api_gateway_rest_api.titanic_api.id
  resource_id             = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method             = aws_api_gateway_method.delete_sobreviventes_id.http_method
  type                    = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "delete_sobreviventes_id_200" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method = aws_api_gateway_method.delete_sobreviventes_id.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "delete_sobreviventes_id_mock_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.titanic_api.id
  resource_id = aws_api_gateway_resource.sobreviventes_id_resource.id
  http_method = aws_api_gateway_method.delete_sobreviventes_id.http_method
  status_code = aws_api_gateway_method_response.delete_sobreviventes_id_200.status_code
  selection_pattern = ""
  response_templates = {
    "application/json" = "{ \"message\": \"DELETE /sobreviventes/{id} mock response. Passageiro deletado.\" }"
  }
}