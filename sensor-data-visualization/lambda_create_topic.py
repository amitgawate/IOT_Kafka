import json
from kafka.admin import KafkaAdminClient, NewTopic
import os

def lambda_handler(event, context):
    kafka_broker = os.environ['KAFKA_BROKER']
    topic_name = event['topic_name']
    num_partitions = event.get('num_partitions', 1)
    replication_factor = event.get('replication_factor', 1)

    admin_client = KafkaAdminClient(
        bootstrap_servers=kafka_broker,
        client_id='lambda-kafka-admin'
    )

    topic_list = []
    topic_list.append(NewTopic(name=topic_name, num_partitions=num_partitions, replication_factor=replication_factor))

    try:
        admin_client.create_topics(new_topics=topic_list, validate_only=False)
        return {
            'statusCode': 200,
            'body': json.dumps(f"Topic '{topic_name}' created successfully.")
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error creating topic: {str(e)}")
        }
