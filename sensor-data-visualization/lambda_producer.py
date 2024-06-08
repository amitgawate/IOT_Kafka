import json
import os
from kafka import KafkaProducer

def lambda_handler(event, context):
    kafka_broker = os.environ['KAFKA_BROKER']
    kafka_topic = os.environ['KAFKA_TOPIC']

    producer = KafkaProducer(
        bootstrap_servers=kafka_broker.split(','),
        value_serializer=lambda x: json.dumps(x).encode('utf-8')
    )

    data = json.loads(event['body'])
    producer.send(kafka_topic, value=data)
    producer.flush()

    return {
        'statusCode': 200,
        'body': json.dumps('Data sent to Kafka')
    }
