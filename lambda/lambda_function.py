import json
import os
import joblib
import pandas as pd
import numpy as np 

# Para interagir com o DynamoDB
import boto3
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE_NAME', 'TitanicSurvivors') # Nome da tabela do DynamoDB

# Caminho do modelo dentro do ambiente Lambda
MODEL_PATH = 'model.pkl'

# Carregar o modelo uma única vez fora da função handler para otimização (warm start)
# Tenta carregar o modelo. Se o arquivo não for encontrado (ex: em testes locais sem o modelo),
# ele definirá o modelo como None e registrará um aviso.
try:
    with open(MODEL_PATH, 'rb') as f:
        model = joblib.load(f)
    print("Modelo ML carregado com sucesso.")
except FileNotFoundError:
    model = None
    print(f"AVISO: Modelo ML não encontrado em {MODEL_PATH}. A escoragem não funcionará sem ele.")
except Exception as e:
    model = None
    print(f"ERRO ao carregar o modelo ML: {e}")

# Definindo as colunas esperadas pelo modelo, na ORDEM CORRETA
# Baseado na análise do seu notebook de treinamento.ipynb
EXPECTED_FEATURES = [
    'Age', 'Parch', 'SibSp', 'Fare', 'Pclass', 'Sex_male', 'Embarked_Q', 'Embarked_S'
]

def preprocess_data(raw_data):
    """
    Prepara os dados brutos JSON para o formato esperado pelo modelo ML.
    Realiza one-hot encoding e tratamento de nulos (fillna(0)).
    """
    df = pd.DataFrame([raw_data])

    # Preencher NaNs com 0 para colunas numéricas (como feito no notebook de treinamento)
    for col in ['Age', 'Fare']:
        if col in df.columns:
            df[col] = df[col].fillna(0)
        else: # Adiciona a coluna se não existir, preenche com 0
            df[col] = 0

    # One-hot encoding para Sex e Embarked
    df['Sex_male'] = df['sex'].apply(lambda x: 1 if x == 'male' else 0)
    df['Embarked_Q'] = df['embarked'].apply(lambda x: 1 if x == 'Q' else 0)
    df['Embarked_S'] = df['embarked'].apply(lambda x: 1 if x == 'S' else 0)

    # Selecionar e reordenar as colunas para corresponder ao EXPECTED_FEATURES
    # Adiciona colunas que podem ter faltado no input com valor 0
    processed_df = pd.DataFrame(0, index=df.index, columns=EXPECTED_FEATURES)
    for feature in EXPECTED_FEATURES:
        if feature in df.columns:
            processed_df[feature] = df[feature]
        # O fillna(0) já foi feito para Age e Fare
        # Para as colunas categóricas one-hot encoded, se elas não existirem no input original,
        # elas já são 0 pelo DataFrame inicial.

    return processed_df

def lambda_handler(event, context):
    http_method = event['httpMethod']
    path = event['path']

    if http_method == 'POST' and path == '/sobreviventes':
        try:
            body = json.loads(event['body'])
            if not isinstance(body, list):
                return {
                    'statusCode': 400,
                    'body': json.dumps({'message': 'Body must be an array of passenger characteristics.'})
                }

            results = []
            for passenger_data in body:
                passenger_id = passenger_data.get('id', 'unknown_id')

                # Remover ID e outras colunas ignoradas antes do pré-processamento
                data_for_prediction = {k: v for k, v in passenger_data.items() if k not in ['id', 'name', 'ticket', 'cabin']}

                # Pré-processar os dados para o formato do modelo
                processed_data = preprocess_data(data_for_prediction)

                if model is None:
                    return {
                        'statusCode': 500,
                        'body': json.dumps({'message': 'Modelo ML não carregado. Verifique os logs da Lambda.'})
                    }

                # Escorar o modelo
                # model.predict_proba retorna [[prob_nao_sobrevive, prob_sobrevive]]
                probabilities = model.predict_proba(processed_data)[0]
                survival_probability = probabilities[1] # Probabilidade de sobreviver

                # Armazenar no DynamoDB (apenas se a tabela for provisionada no futuro)
                # if table_name: # Verifica se o nome da tabela existe
                #     try:
                #         table = dynamodb.Table(table_name)
                #         table.put_item(
                #             Item={
                #                 'PassengerId': passenger_id,
                #                 'SurvivalProbability': float(survival_probability), # Converte para float nativo
                #                 'Timestamp': pd.Timestamp.now().isoformat()
                #             }
                #         )
                #     except Exception as db_e:
                #         print(f"Erro ao armazenar no DynamoDB: {db_e}")
                #         # Não falha a API por erro de DB para o case, mas registra.

                results.append({
                    'id': passenger_id,
                    'survival_probability': float(survival_probability) # Converte para float nativo
                })

            return {
                'statusCode': 200,
                'headers': { 'Content-Type': 'application/json' },
                'body': json.dumps(results)
            }

        except json.JSONDecodeError:
            return {
                'statusCode': 400,
                'body': json.dumps({'message': 'Invalid JSON in request body.'})
            }
        except Exception as e:
            print(f"Erro no POST /sobreviventes: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps({'message': f'Internal server error: {str(e)}'})
            }

    elif http_method == 'GET' and path == '/sobreviventes':
        # Implementação do GET /sobreviventes (lista de avaliados)
        # Para o case, dado que DynamoDB não será provisionado, podemos retornar um mock ou lista vazia.
        # Se DynamoDB fosse provisionado, a lógica de consulta viria aqui.
        return {
            'statusCode': 200,
            'headers': { 'Content-Type': 'application/json' },
            'body': json.dumps({'message': 'GET /sobreviventes - Lista de passageiros avaliados (implementação pendente sem DynamoDB provisionado).'})
        }

    elif http_method == 'GET' and path.startswith('/sobreviventes/'):
        # Implementação do GET /sobreviventes/{id}
        # Extrair ID do path
        passenger_id = path.split('/')[-1]
        return {
            'statusCode': 200,
            'headers': { 'Content-Type': 'application/json' },
            'body': json.dumps({
                'message': f'GET /sobreviventes/{passenger_id} - Detalhes do passageiro (implementação pendente sem DynamoDB provisionado).',
                'id': passenger_id
            })
        }

    elif http_method == 'DELETE' and path.startswith('/sobreviventes/'):
        # Implementação do DELETE /sobreviventes/{id}
        # Extrair ID do path
        passenger_id = path.split('/')[-1]
        return {
            'statusCode': 200,
            'headers': { 'Content-Type': 'application/json' },
            'body': json.dumps({
                'message': f'DELETE /sobreviventes/{passenger_id} - Passageiro deletado (implementação pendente sem DynamoDB provisionado).',
                'id': passenger_id
            })
        }

    return {
        'statusCode': 404,
        'body': json.dumps({'message': 'Resource not found.'})
    }