import requests
import logging
import time

# Настройка логирования
logger = logging.getLogger(__name__)

def extract_openmeteo_raw(lat, lon, start_date, end_date, retries=3):
    """
    Args:
        lat (float): широта
        lon (float): долгота
        start_date (str): начало периода в формате YYYY-MM-DD
        end_date (str): конец периода в формате YYYY-MM-DD
        retries (int): количество повторных попыток при сбое запроса, по умолчанию три

    Возвращает JSON с данными от Open-Meteo API
    """

    # URL API
    url = "https://historical-forecast-api.open-meteo.com/v1/forecast"

    # задаем параметры запроса
    params = {
        "latitude": lat,
        "longitude": lon,
        "start_date": start_date,
        "end_date": end_date,
        "hourly": ",".join([
            "temperature_2m",
            "apparent_temperature",
            "dewpoint_2m",
            "relativehumidity_2m",
            "precipitation",
            "rain",
            "snowfall",
            "cloudcover",
            "cloudcover_low",
            "cloudcover_mid",
            "cloudcover_high",
            "surface_pressure",
            "pressure_msl",
            "visibility",
            "windspeed_10m",
            "windgusts_10m",
            "winddirection_10m",
            "weathercode"
        ]),
        "timezone": "UTC"
    }

    # основной цикл с retry
    for attempt in range(1, retries + 1):
        try:
            logger.info(f"Запрос к Open-Meteo API: попытка {attempt}")
            
            # выполняем GET-запрос
            response = requests.get(url, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()

            # проверка структуры данных
            if "hourly" not in data or not data["hourly"]:
                raise ValueError("Нет данных 'hourly' в ответе API")

            # успешная загрузка
            hourly_count = len(data['hourly'].get('time', []))
            logger.info(f"Успешно извлечено {hourly_count} почасовых записей")

            # добавляем метаданные запроса
            return {
                "lat": lat,
                "lon": lon,
                "start_date": start_date,
                "end_date": end_date,
                "data": data
            }

        except requests.RequestException as e:
            logger.warning(f"Сетевая ошибка на попытке {attempt}: {e}")

        except ValueError as e:
            logger.error(f"Ошибка данных на попытке {attempt}: {e}")
            raise

        if attempt < retries:
            sleep_time = 2 ** attempt
            logger.info(f"Повтор через {sleep_time} секунд...")
            time.sleep(sleep_time)

    raise RuntimeError("Не удалось извлечь данные с Open-Meteo API после нескольких попыток")