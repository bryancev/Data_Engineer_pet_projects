import pytest
import requests

# импортируем тестируемую функцию
from etl.extract.open_meteo_hourly import extract_openmeteo_raw


# mock ответа API
class MockResponse:
    """
    Класс-имитация объекта requests.Response.
    Позволяет подменить реальный ответ API в тестах.
    """
    def __init__(self, json_data, status_code=200, raise_exc=False):
        self._json = json_data          # заранее заданный JSON
        self.status_code = status_code  # HTTP-статус

    # метод, имитирующий response.json()
    def json(self):
        return self._json

    # метод, имитирующий поведение requests
    def raise_for_status(self):
        if self.status_code != 200:
            raise requests.RequestException("HTTP error")


# тест успешного ответа
def test_extract_success(monkeypatch):
    """
    Проверяем, что функция корректно обрабатывает успешный ответ API
    и возвращает ожидаемую структуру данных.
    """

    # фейковый JSON, который "вернул API"
    mock_json = {
        "hourly": {
            "time": ["2026-02-19T00:00"],
            "temperature_2m": [25.0]
        }
    }

    # подменяем requests.get(), он будет возвращать наш MockResponse
    def mock_get(*args, **kwargs):
        return MockResponse(mock_json)

    monkeypatch.setattr("requests.get", mock_get)

    # вызываем extract
    data = extract_openmeteo_raw(
        lat=8.1,
        lon=98.3,
        start_date="2026-02-19",
        end_date="2026-02-20"
    )

    # проверки результата
    assert isinstance(data, dict)                   # вернулся словарь
    assert "hourly" in data["data"]                 # есть ключ hourly
    assert len(data["data"]["hourly"]["time"]) > 0  # есть хотя бы одна временная метка


# тест отсутствия hourly
def test_extract_no_hourly(monkeypatch):
    """
    Проверяем, что функция выбрасывает ValueError,
    если в ответе API нет ключа 'hourly'.
    """

    mock_json = {}  # некорректный ответ API

    def mock_get(*args, **kwargs):
        return MockResponse(mock_json)

    monkeypatch.setattr("requests.get", mock_get)

    # ожидаем исключение
    with pytest.raises(ValueError):
        extract_openmeteo_raw(
            lat=8.1,
            lon=98.3,
            start_date="2026-02-19",
            end_date="2026-02-20"
        )


# тест retry (ошибка сети, потом успех)
def test_extract_retry_success(monkeypatch):
    """
    Проверяем, что retry работает:
    первая попытка падает, вторая — успешна.
    """

    mock_json = {
        "hourly": {
            "time": ["2026-02-19T00:00"],
        }
    }

    # счётчик вызовов requests.get
    calls = {"count": 0}

    def mock_get(*args, **kwargs):
        calls["count"] += 1

        # первая попытка — ошибка
        if calls["count"] < 2:
            raise requests.RequestException("Temporary error")

        # вторая попытка — успех
        return MockResponse(mock_json)

    monkeypatch.setattr("requests.get", mock_get)
    monkeypatch.setattr("time.sleep", lambda x: None)  # убираем реальные задержки

    data = extract_openmeteo_raw(
        lat=8.1,
        lon=98.3,
        start_date="2026-02-19",
        end_date="2026-02-20",
        retries=3
    )

    # проверяем, что было 2 попытки
    assert calls["count"] == 2

    # и в итоге получили данные
    assert "hourly" in data["data"]


# тест полного падения после retry
def test_extract_retry_fail(monkeypatch):
    """
    Проверяем, что если все попытки завершаются ошибкой,
    функция выбрасывает RuntimeError.
    """

    # всегда ошибка сети
    def mock_get(*args, **kwargs):
        raise requests.RequestException("Network error")

    monkeypatch.setattr("requests.get", mock_get)
    monkeypatch.setattr("time.sleep", lambda x: None)  # убираем реальные задержки

    # ожидаем RuntimeError после всех retry
    with pytest.raises(RuntimeError):
        extract_openmeteo_raw(
            lat=8.1,
            lon=98.3,
            start_date="2026-02-19",
            end_date="2026-02-20",
            retries=2
        )

# --- ТЕСТЫ ЛОГИРОВАНИЯ ---
# тест логирования успешного выполнения 
def test_logging_success(monkeypatch, caplog):
    """
    Проверяем, что при успешном выполнении функции
    логируется сообщение об успешном извлечении данных.
    """

    mock_json = {
        "hourly": {
            "time": ["2026-02-19T00:00"],
        }
    }

    def mock_get(*args, **kwargs):
        return MockResponse(mock_json)

    monkeypatch.setattr("requests.get", mock_get)

    # включаем перехват логов уровня INFO
    caplog.set_level("INFO")

    extract_openmeteo_raw(
        lat=8.1,
        lon=98.3,
        start_date="2026-02-19",
        end_date="2026-02-20"
    )

    # проверяем, что в логе есть сообщение об успехе
    assert "Успешно извлечено" in caplog.text


# тест логирования сетевой ошибки (retry)
def test_logging_retry_warning(monkeypatch, caplog):
    """
    Проверяем, что при сетевой ошибке логируется warning
    и выполняется повторная попытка.
    """

    calls = {"count": 0}

    def mock_get(*args, **kwargs):
        calls["count"] += 1

        # первая попытка — ошибка
        if calls["count"] < 2:
            raise requests.RequestException("Temporary error")

        return MockResponse({
            "hourly": {"time": ["2026-02-19T00:00"]}
        })

    monkeypatch.setattr("requests.get", mock_get)

    caplog.set_level("WARNING")

    extract_openmeteo_raw(
        lat=8.1,
        lon=98.3,
        start_date="2026-02-19",
        end_date="2026-02-20",
        retries=2
    )

    # проверяем, что warning записался
    assert "Сетевая ошибка" in caplog.text


# тест логирования ошибки данных
def test_logging_data_error(monkeypatch, caplog):
    """
    Проверяем, что при некорректной структуре данных
    логируется ошибка (error).
    """

    mock_json = {}  # нет hourly

    def mock_get(*args, **kwargs):
        return MockResponse(mock_json)

    monkeypatch.setattr("requests.get", mock_get)

    caplog.set_level("ERROR")

    with pytest.raises(ValueError):
        extract_openmeteo_raw(
            lat=8.1,
            lon=98.3,
            start_date="2026-02-19",
            end_date="2026-02-20"
        )

    # проверяем, что ошибка залогировалась
    assert "Ошибка данных" in caplog.text


# тест логирования полного падения
def test_logging_final_error(monkeypatch, caplog):
    """
    Проверяем, что при полном падении API
    логируются сетевые ошибки перед RuntimeError.
    """

    def mock_get(*args, **kwargs):
        raise requests.RequestException("Network error")

    monkeypatch.setattr("requests.get", mock_get)

    caplog.set_level("WARNING")

    with pytest.raises(RuntimeError):
        extract_openmeteo_raw(
            lat=8.1,
            lon=98.3,
            start_date="2026-02-19",
            end_date="2026-02-20",
            retries=2
        )

    # проверяем, что ошибки были в логе
    assert "Сетевая ошибка" in caplog.text