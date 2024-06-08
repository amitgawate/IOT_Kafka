package com.example;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SNSEvent;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.influxdb.client.InfluxDBClient;
import com.influxdb.client.InfluxDBClientFactory;
import com.influxdb.client.InfluxDBClientOptions;
import com.influxdb.client.WriteApiBlocking;
import com.influxdb.client.domain.WritePrecision;
import com.influxdb.client.write.Point;
import okhttp3.OkHttpClient;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.net.UnknownHostException;

import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URL;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

public class LambdaKafkaInfluxDBHandler implements RequestHandler<SNSEvent, String> {

    private static final Logger logger = LoggerFactory.getLogger(LambdaKafkaInfluxDBHandler.class);
    private static final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public String handleRequest(SNSEvent event, Context context) {
        String kafkaBroker = System.getenv("KAFKA_BROKER");
        String kafkaTopic = System.getenv("KAFKA_TOPIC");
        String influxdbUrl = System.getenv("INFLUXDB_URL");
        String influxdbToken = "DiDRY-QbGFHD8tGyB7m2n0mfy9Ifa5GGPl58fgZGAR_xIzANPHgBA63zti_fOHTiiA2iHhp1oUDFN2vv3T4v_w==";
        String influxdbOrg = System.getenv("INFLUXDB_ORG");
        String influxdbBucket = System.getenv("INFLUXDB_BUCKET");

        logger.info("kafkaBroker: " + kafkaBroker);
        logger.info("kafkaTopic: " + kafkaTopic);
        logger.info("influxdbUrl: " + influxdbUrl);
        logger.info("influxdbOrg: " + influxdbOrg);
        logger.info("influxdbBucket: " + influxdbBucket);
        logger.info("influxdbToken: " + influxdbToken);

        // Ping Google to verify connectivity
        if (pingGoogle()) {
            logger.info("Ping to google.com successful.");
        } else {
            logger.error("Ping to google.com failed.");
        }

        // Increase timeout settings for InfluxDBClient
        OkHttpClient.Builder httpClient = new OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS);

        // Create InfluxDBClientOptions with the custom OkHttpClient
        InfluxDBClientOptions options = InfluxDBClientOptions.builder()
                .url(influxdbUrl)
                .authenticateToken(influxdbToken.toCharArray())
                .org(influxdbOrg)
                .bucket(influxdbBucket)
                .okHttpClient(httpClient)
                .build();

        InfluxDBClient influxDBClient = InfluxDBClientFactory.create(options);
        WriteApiBlocking writeApi = influxDBClient.getWriteApiBlocking();

        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, kafkaBroker);
        String groupId = "consumer-lambda-group-" + UUID.randomUUID();
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringDeserializer");
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringDeserializer");
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "true");

        KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);
        consumer.subscribe(Collections.singletonList(kafkaTopic));

        try {
            while (true) {
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
                for (ConsumerRecord<String, String> record : records) {
                    String value = record.value();

                    logger.info("SensorData: " + value);

                    SensorData data = parseSensorData(value);

                    Point point = Point.measurement("sensor_data")
                            .addTag("source", "raspberry_pi")
                            .addField("temperature", data.getTemperature())
                            .addField("humidity", data.getHumidity())
                            .addField("motion", data.getMotion())
                            .time(System.currentTimeMillis(), WritePrecision.MS);

                    writeApi.writePoint(point);
                    logger.info("Stored data: " + value);
                }
            }
        } catch (Exception e) {
            logger.error("Error processing records", e);
        } finally {
            consumer.close();
            influxDBClient.close();
        }

        return "Data processed successfully!";
    }

    private boolean pingGoogle() {
        try {
            // Check DNS resolution
            InetAddress google = InetAddress.getByName("www.google.com");
            logger.info("DNS resolution for google.com: " + google.getHostAddress());

            // Attempt to connect to google.com
            URL url = new URL("http://www.google.com");
            HttpURLConnection urlConn = (HttpURLConnection) url.openConnection();
            urlConn.setConnectTimeout(5000); // 5 seconds timeout
            urlConn.connect();
            int responseCode = urlConn.getResponseCode();
            logger.info("Response code from google.com: " + responseCode);
            return responseCode == 200;
        } catch (UnknownHostException e) {
            logger.error("DNS resolution failed for google.com", e);
            return false;
        } catch (IOException e) {
            logger.error("Failed to ping google.com", e);
            return false;
        }
    }


    private SensorData parseSensorData(String json) {
        try {
            JsonNode node = objectMapper.readTree(json);
            double temperature = node.get("temperature").asDouble();
            double humidity = node.get("humidity").asDouble();
            double motion = node.get("motion").asDouble();
            return new SensorData(temperature, humidity, motion);
        } catch (Exception e) {
            logger.error("Failed to parse sensor data: " + json, e);
            return new SensorData(0.0, 0.0, 0.0); // Return a default SensorData object in case of error
        }
    }

    private static class SensorData {
        private double temperature;
        private double humidity;
        private double motion;

        public SensorData(double temperature, double humidity, double motion) {
            this.temperature = temperature;
            this.humidity = humidity;
            this.motion = motion;
        }

        public double getTemperature() {
            return temperature;
        }

        public double getHumidity() {
            return humidity;
        }

        public double getMotion() {
            return motion;
        }
    }
}
