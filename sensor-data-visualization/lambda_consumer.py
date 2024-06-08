import json
import os
from kafka import KafkaConsumer
from influxdb_client import InfluxDBClient, Point, WriteOptions

def lambda_handler(event, context):
    kafka_brokers = os.environ['KAFKA_BROKER'].split(',')
    kafka_topic = os.environ['KAFKA_TOPIC']
    influxdb_url = os.environ['INFLUXDB_URL']
    # influxdb_token = os.environ['INFLUXDB_TOKEN']
    influxdb_token = 'PItsAVRwENvOyceHXXqDlCKTRQMseq8FMOlb5gzUHKZmsg5d1p_TqjATnWOPTQt-E7x2WV3o1By4Hmdy_37UhQ=='
    influxdb_org = os.environ['INFLUXDB_ORG']
    influxdb_bucket = os.environ['INFLUXDB_BUCKET']

    try:
        consumer = KafkaConsumer(
            kafka_topic,
            bootstrap_servers=kafka_brokers,
            value_deserializer=lambda x: json.loads(x.decode('utf-8'))
        )
    except Exception as e:
        print(f"Failed to initialize Kafka consumer: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Failed to initialize Kafka consumer: {e}")
        }

    try:
        influx_client = InfluxDBClient(
            url=influxdb_url,
            token=influxdb_token,
            org=influxdb_org
        )
        write_api = influx_client.write_api(write_options=WriteOptions(batch_size=1))
    except Exception as e:
        print(f"Failed to initialize InfluxDB client: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Failed to initialize InfluxDB client: {e}")
        }

    for message in consumer:
        try:
            data = message.value
            point = Point("sensor_data") \
                .tag("source", "raspberry_pi") \
                .field("temperature", data['temperature']) \
                .field("humidity", data['humidity']) \
                .field("motion", data['motion'])
            write_api.write(bucket=influxdb_bucket, record=point)
            print(f"Stored data: {data}")
        except Exception as e:
            print(f"Failed to process message {message}: {e}")

    return {
        'statusCode': 200,
        'body': json.dumps('Data processed successfully!')
    }
