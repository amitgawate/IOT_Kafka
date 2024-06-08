# IOT_Kafka
Sending sensor data to InfluxDB/Grafana through MSK(Kafka) 

## InfluxDB

Connect to EC2 instanace
- sudo docker ps
- influx bucket list --org my-org (get the ID)
- influx auth create --org my-org --read-bucket 62f56e38e4ab0d76 --write-bucket 62f56e38e4ab0d76 --description "Read/Write Token"


/repos/kafka/sensor-data-visualization/java_consumer_function
mvn clean package
cp ./target/lambda-kafka-influxdb-1.0-SNAPSHOT.jar ../terraform/target


# lambda producer

pip install kafka-python -t .


#SSH to Raspberry Pi
ssh pi@192.168.86.21