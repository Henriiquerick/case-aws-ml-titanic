import json
import boto3
import os
import joblib
from botocore.exceptions import NoCredentialsError, PartialCredentialsError
import pandas as pd
import logging
from encoder_decimal import CustomEncoder # O arquivo que você acabou de criar!
import sklearn # Garante que scikit-learn esteja acessível
import sys # Para uso opcional em depuração, se necessário
from decimal import Decimal # Para lidar com números do DynamoDB

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Inicialize o cliente DynamoDB e s3
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3') # Cliente S3 para baixar o modelo

# Obtenha o nome da tabela e do bucket/chave do modelo a partir das variáveis de ambiente
table_name = os.environ.get('DYNAMODB_TABLE') # O nome da tabela DynamoDB (ex: "TitanicSurvivors")
table = dynamodb.Table(table_name) # Inicializa a tabela DynamoDB

bucket_name = os.environ.get('S3_BUCKET_NAME') # O nome do bucket S3 onde está o modelo
model_key = os.environ.get('S3_MODEL_KEY') # A chave do modelo no S3 (ex: "model.pkl")


# Função para carregar o modelo do S3
def load_model_from_s3(bucket_name, model_key):
    try:
        logger.info(f"Loading model from bucket: {bucket_name}, key: {model_key}")
        # Baixa o modelo para o diretório temporário da Lambda (/tmp/)
        # /tmp/ é o único diretório gravável na Lambda
        s3.download_file(bucket_name, model_key, '/tmp/model.pkl') 
        with open('/tmp/model.pkl', 'rb') as f:
            model = joblib.load(f)
        logger.info(f"Model loaded: {model}")
        return model
    except Exception as e:
        logger.error(f"ERROR loading model from S3: {str(e)}")
        raise # Levanta a exceção para que a Lambda falhe e o erro seja visto

# Carrega o modelo UMA VEZ ao inicializar a Lambda (warm start)
model = load_model_from_s3(bucket_name, model_key)

# Definindo as colunas esperadas pelo modelo, na ORDEM CORRETA
# Baseado na análise do seu notebook de treinamento.ipynb do gabarito.
# O gabarito espera que esses dados já venham pré-processados na entrada POST.
EXPECTED_FEATURES = [
    'Age', 'Parch', 'SibSp', 'Fare', 'Pclass', 'Sex_male', 'Embarked_Q', 'Embarked_S'
]

# Variáveis para roteamento dos métodos HTTP
getMethod = 'GET'
postMethod = 'POST'
deleteMethod = 'DELETE'
healthPath = '/health' # Novo endpoint para checagem de saúde
endpointPath = '/sobreviventes' # Endpoint principal para passageiros

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}") # Loga o evento completo para depuração
    httpMethod = event['httpMethod']
    path = event['path']
    # Para GET /sobreviventes?id=xxx, os parâmetros de consulta vêm aqui
    query_string_parameters = event.get('queryStringParameters') 
    # Para GET/DELETE /sobreviventes/{id}, os parâmetros de caminho vêm aqui
    path_parameters = event.get('pathParameters')

    try:
        # Roteamento dos métodos da API Gateway para as funções Python
        if httpMethod == getMethod and path == healthPath:
            # Verifica a saúde da API.
            response = buildResponse(200, {'message': 'Health check successful'})

        elif httpMethod == getMethod and path == endpointPath:
            # Retorna a lista de todos os passageiros analisados OU um específico por ID de query string
            if query_string_parameters and 'id' in query_string_parameters:
                passenger_id = query_string_parameters['id']
                response = getId(passenger_id)
            else:
                response = getPassengers()

        elif httpMethod == postMethod and path == endpointPath:
            # Escora o modelo para o passageiro com as informações enviadas no corpo da requisição.
            response = scoreModel(event)

        elif httpMethod == deleteMethod and path.startswith(endpointPath + '/'):
            # Deleta o passageiro com o ID especificado no caminho.
            if path_parameters and 'id' in path_parameters:
                passenger_id = path_parameters['id']
                response = deleteId(passenger_id)
            else:
                response = buildResponse(400, {'message': 'Missing passenger ID in path for DELETE method.'})

        else:
            # Se o caminho ou método não corresponder, retorna Not Found.
            response = buildResponse(404, {'message': 'Resource not found.'})
            
    except Exception as e:
        logger.exception(f"Error handling request: {str(e)}") # Loga a exceção completa
        response = buildResponse(500, {'message': f'Internal Server Error: {str(e)}'})

    return response

# Função para escorar o modelo e salvar no DynamoDB
def scoreModel(event):
    # O modelo já está carregado globalmente (warm start)
    if model is None:
        logger.error("Model is not loaded. Cannot score.")
        return buildResponse(500, {'message': 'Model not loaded. Check Lambda logs.'})

    try:
        logger.info("Attempting to score model.")
        data_raw = json.loads(event['body']) # Espera um ÚNICO objeto JSON
        logger.info(f"Data received for scoring: {data_raw}")

        # O gabarito espera que as features já venham pré-processadas no JSON de entrada.
        # Não há mais a função preprocess_data aqui.
        # Garante que as features estão na ordem correta que o modelo espera.
        input_features = pd.DataFrame([data_raw])[EXPECTED_FEATURES]
        
        prediction = model.predict_proba(input_features)[0][1] # Probabilidade de sobreviver
        logger.info(f"Prediction result: {prediction}")
    
        # Prepara o item para salvar no DynamoDB. Usa CustomEncoder para lidar com Decimal.
        item = {
            "id": str(data_raw.get("id", "no_id_provided")), # Garante que o ID é string
            "features": json.dumps(data_raw, cls=CustomEncoder), # Salva as features originais como string
            "prediction": Decimal(str(round(prediction, 4))) # Salva a predição como Decimal, arredondada
        }
        
        # Salva o item no DynamoDB
        table.put_item(Item=item)
        logger.info(f"Item successfully saved to DynamoDB: {item.get('id')}")

        return buildResponse(200, {'id': data_raw.get('id', 'no_id_provided'), 'prediction': float(prediction)})

    except Exception as e:
        logger.exception(f"ERROR scoring model: {str(e)}")
        return buildResponse(500, {'message': f'Error scoring model: {str(e)}'})

# Função auxiliar para construir as respostas HTTP
def buildResponse(status_code, body=None):
    response = {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json'
        }
    }
    if body is not None:
        response['body'] = json.dumps(body, cls=CustomEncoder) # Usa CustomEncoder para todas as respostas
    else:
        response['body'] = json.dumps({}) # Retorna um objeto JSON vazio se não houver corpo

    return response

# Função para obter um passageiro por ID do DynamoDB
def getId(passengerId):
    try:
        logger.info(f"Getting passenger with ID: {passengerId} from DynamoDB.")
        response = table.get_item(
            Key={
                'id': passengerId
            }
        )
        if 'Item' in response:
            logger.info(f"Passenger found: {response['Item'].get('id')}")
            return buildResponse(200, response['Item'])
        else:
            logger.warning(f"Passenger with ID: {passengerId} not found.")
            return buildResponse(404, {'Message': f'ID: {passengerId} not found'})
    except Exception as e:
        logger.exception(f"Error getting passenger by ID: {str(e)}")
        return buildResponse(500, {'message': f'Error getting passenger by ID: {str(e)}'})

# Função para listar todos os passageiros do DynamoDB
def getPassengers():
    try:
        logger.info("Scanning DynamoDB for all passengers.")
        response = table.scan()
        items = response.get('Items', [])

        while 'LastEvaluatedKey' in response:
            response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response.get('Items', []))

        body = {
            'passengers': items
        }
        logger.info(f"Retrieved {len(items)} passengers.")
        return buildResponse(200, body)
    except Exception as e:
        logger.exception(f"Error getting all passengers: {str(e)}")
        return buildResponse(500, {'message': f'Error getting passengers: {str(e)}'})

# Função para deletar um passageiro do DynamoDB
def deleteId(passenger_id):
    try:
        logger.info(f"Deleting passenger with ID: {passenger_id} from DynamoDB.")
        response = table.delete_item(
            Key={
                'id': passenger_id
            },
            ReturnValues='ALL_OLD' # Retorna o item que foi deletado
        )
        body = {
            'Operation': 'DELETE',
            'Message': 'SUCCESS',
            'deletedItem': response.get('Attributes', {}) # 'Attributes' contém o item deletado
        }
        logger.info(f"Passenger {passenger_id} deleted successfully.")
        return buildResponse(200, body)
    except Exception as e:
        logger.exception(f"Error deleting passenger: {str(e)}")
        return buildResponse(500, {'message': f'Error deleting passenger: {str(e)}'})