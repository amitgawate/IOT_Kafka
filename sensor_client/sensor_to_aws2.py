import time
import board
import adafruit_dht
import requests
import random

# Initialize the DHT device, with data pin connected to:
dhtDevice = adafruit_dht.DHT11(board.D4)  # Change D4 to the pin you are using

# AWS API Gateway URL
api_url = 'https://xq7lfnc2u1.execute-api.us-east-1.amazonaws.com/prod/send'

# Exponential backoff configuration
INITIAL_BACKOFF = 1  # initial backoff time in seconds
MAX_BACKOFF = 32  # maximum backoff time in seconds
MAX_RETRIES = 5  # maximum number of retries

def read_sensor():
    try:
        # Print the values to the serial port
        temperature_c = dhtDevice.temperature
        humidity = dhtDevice.humidity

        # Convert temperature to Fahrenheit
        temperature_f = temperature_c * (9 / 5) + 32

        return temperature_f, humidity
    except RuntimeError as error:
        # Errors happen fairly often, DHT's are hard to read, just keep going
        print(error.args[0])
        return None, None
    except Exception as error:
        dhtDevice.exit()
        raise error

def send_to_aws(temperature, humidity, motion):
    data = {
        "temperature": temperature,
        "humidity": humidity,
        "motion": motion
    }
    backoff = INITIAL_BACKOFF
    retries = 0

    while retries < MAX_RETRIES:
        try:
            response = requests.post(api_url, json=data)
            if response.status_code == 200:
                print('Data sent successfully  ')
                print(data)
                return True
            else:
                print(f'Failed to send data. Status code: {response.status_code}')
        except requests.exceptions.RequestException as e:
            print(f'Request failed: {e}')

        retries += 1
        sleep_time = backoff + random.uniform(0, 1)  # Adding jitter
        print(f'Waiting {sleep_time:.1f} seconds before retrying...')
        time.sleep(sleep_time)
        backoff = min(backoff * 2, MAX_BACKOFF)  # Exponential backoff

    print('Failed to send data after maximum retries')
    return False

def main():
    while True:
        temperature, humidity = read_sensor()
        if temperature is not None and humidity is not None:
            # Replace this with actual motion sensor data if you have one
            motion_detected = True  # Placeholder for motion sensor data
            send_to_aws(temperature, humidity, motion_detected)
        time.sleep(5)

if __name__ == "__main__":
    main()