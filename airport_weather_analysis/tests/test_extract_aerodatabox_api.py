import pytest
import requests
import logging
import time

from etl.extract.aerodatabox_api import extract_aerodatabox_fids_range_batch


# класс для имитации ответов requests
class MockResponse:

    def __init__(self, json_data=None, status_code=200, headers=None, raise_exc=False):
        self._json = json_data or {}
        self.status_code = status_code
        self.headers = headers or {}
        self.raise_exc = raise_exc

    def json(self):
        return self._json

    def raise_for_status(self):
        if self.raise_exc or self.status_code >= 400:
            raise requests.RequestException("HTTP error")


# фикстуры
@pytest.fixture(autouse=True)
def mock_api_key(monkeypatch):
    # автоматически подставляем фейковый API-ключ во все тесты
    monkeypatch.setenv("AERODATABOX_API_KEY", "test_key")


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    # отключаем задержки внутри функции,
    # чтобы ускорить выполнение всех тестов
    monkeypatch.setattr(time, "sleep", lambda seconds: None)


# ---------------------------------------------------------
# ТЕСТЫ ДАТ
# ---------------------------------------------------------

# проверяем, что начальная дата обязательна
def test_no_start_date():
    with pytest.raises(TypeError):
        extract_aerodatabox_fids_range_batch(
            airport_code="HKT",
            code_type="IATA",
            end_date="2026-02-19"
        )


# проверяем, что конечная дата обязательна
def test_no_end_date():
    with pytest.raises(TypeError):
        extract_aerodatabox_fids_range_batch(
            airport_code="HKT",
            code_type="IATA",
            start_date="2026-02-19"
        )


# проверяем, что конечная дата не может быть раньше начальной
def test_invalid_date_range():
    with pytest.raises(
        ValueError,
        match="end_date must be greater than or equal to start_date"
    ):
        extract_aerodatabox_fids_range_batch(
            airport_code="HKT",
            code_type="IATA",
            start_date="2026-02-20",
            end_date="2026-02-19"
        )


# проверяем диапазон из одного дня
def test_single_day_range(monkeypatch):
    calls = {"count": 0}

    def mock_get(*args, **kwargs):
        calls["count"] += 1
        return MockResponse({"departures": []})

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    # один день = два окна по 12 часов
    assert len(data) == 2
    assert calls["count"] == 2


# проверяем диапазон из нескольких дней
def test_multiple_days_range(monkeypatch):
    def mock_get(*args, **kwargs):
        return MockResponse({"departures": []})

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-21"
    )

    # 3 дня × 2 окна = 6 батчей
    assert len(data) == 6


# ---------------------------------------------------------
# ТЕСТ УСПЕШНОГО СЦЕНАРИЯ
# ---------------------------------------------------------

def test_extract_success(monkeypatch):
    # проверяем, что функция корректно возвращает данные
    # при успешном запросе
    mock_json = {
        "departures": [
            {"flight": "AB123"}
        ]
    }

    def mock_get(*args, **kwargs):
        return MockResponse(mock_json)

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    # проверяем структуру данных
    assert isinstance(data, list)
    assert len(data) == 2
    assert "payload" in data[0]
    assert "departures" in data[0]["payload"]


# ---------------------------------------------------------
# ТЕСТ API-КЛЮЧА
# ---------------------------------------------------------

# проверяем сценарий отсутствия API-ключа
def test_no_api_key(monkeypatch):
    monkeypatch.delenv("AERODATABOX_API_KEY", raising=False)

    with pytest.raises(RuntimeError):
        extract_aerodatabox_fids_range_batch(
            airport_code="HKT",
            code_type="IATA",
            start_date="2026-02-19",
            end_date="2026-02-19"
        )


# ---------------------------------------------------------
# ТЕСТ ПУСТОГО ОТВЕТА
# ---------------------------------------------------------

# проверяем обработку пустого ответа API (HTTP 204)
def test_empty_response(monkeypatch):

    def mock_get(*args, **kwargs):
        return MockResponse(status_code=204)

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    # ожидаем, что payload будет с пустым списком flights
    assert data[0]["payload"]["flights"] == []


# ---------------------------------------------------------
# ТЕСТЫ RETRY
# ---------------------------------------------------------

# проверяем retry при HTTP 429 (rate limit)
def test_rate_limit_retry(monkeypatch):
    calls = {"count": 0}

    def mock_get(*args, **kwargs):
        calls["count"] += 1

        if calls["count"] == 1:
            return MockResponse(
                status_code=429,
                headers={"Retry-After": "1"}
            )

        return MockResponse({"departures": []})

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    # проверяем, что было хотя бы 2 попытки
    assert calls["count"] >= 2
    assert len(data) > 0


# тест проверки при сетевых ошибках
def test_network_retry(monkeypatch):
    calls = {"count": 0}

    def mock_get(*args, **kwargs):
        calls["count"] += 1

        if calls["count"] < 2:
            raise requests.RequestException("Network error")

        return MockResponse({"departures": []})

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    assert calls["count"] >= 2
    assert len(data) > 0


# ---------------------------------------------------------
# ТЕСТ НЕУСПЕШНОГО RETRY
# ---------------------------------------------------------

# тест худшего сценария
def test_retry_fail(monkeypatch):

    def mock_get(*args, **kwargs):
        raise requests.RequestException("Always fail")

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    # функция не падает, возвращает пустой список
    assert data == []


# ---------------------------------------------------------
# ТЕСТ ВАЛИДАЦИИ PAYLOAD
# ---------------------------------------------------------

# проверка обработки некорректного ответа API (не словарь)
def test_invalid_payload(monkeypatch):

    def mock_get(*args, **kwargs):
        return MockResponse(json_data="not a dict")

    monkeypatch.setattr("requests.get", mock_get)

    data = extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    # такие батчи пропускаются
    assert data == []


# ---------------------------------------------------------
# ТЕСТЫ ЛОГИРОВАНИЯ
# ---------------------------------------------------------

# проверяем, что INFO логи создаются
# для каждого запроса и по завершению
def test_logging_info_for_request(monkeypatch, caplog):
    caplog.set_level(logging.INFO)

    def mock_get(*args, **kwargs):
        return MockResponse({
            "departures": [],
            "arrivals": []
        })

    monkeypatch.setattr("requests.get", mock_get)

    extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    info_logs = [
        r.message
        for r in caplog.records
        if r.levelno == logging.INFO
    ]

    # лог запроса
    assert any(
        "AeroDataBox HKT" in msg
        for msg in info_logs
    )

    # лог завершения extract
    assert any(
        "Extract completed" in msg
        for msg in info_logs
    )


# проверяем WARNING лог при HTTP 429
def test_logging_warning_for_rate_limit(monkeypatch, caplog):
    caplog.set_level(logging.WARNING)

    calls = {"count": 0}

    def mock_get(*args, **kwargs):
        calls["count"] += 1

        if calls["count"] == 1:
            return MockResponse(
                status_code=429,
                headers={}
            )

        return MockResponse({"departures": []})

    monkeypatch.setattr("requests.get", mock_get)

    extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    warnings = [
        r.message
        for r in caplog.records
        if r.levelno == logging.WARNING
    ]

    assert any(
        "429 rate limit" in w
        for w in warnings
    )


# проверяем лог ошибки,
# если все retry неудачны
def test_logging_error_after_retries(monkeypatch, caplog):
    caplog.set_level(logging.ERROR)

    def mock_get(*args, **kwargs):
        raise requests.RequestException("Always fail")

    monkeypatch.setattr("requests.get", mock_get)

    extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    errors = [
        r.message
        for r in caplog.records
        if r.levelno == logging.ERROR
    ]

    assert any(
        "skipped" in e
        for e in errors
    )


# проверяем WARNING,
# если ответ API не содержит departures/arrivals
def test_logging_warning_missing_keys(monkeypatch, caplog):
    caplog.set_level(logging.WARNING)

    def mock_get(*args, **kwargs):
        return MockResponse(
            json_data={"something_else": 123}
        )

    monkeypatch.setattr("requests.get", mock_get)

    extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    warnings = [
        r.message
        for r in caplog.records
        if r.levelno == logging.WARNING
    ]

    assert any(
        "Нет ключей arrivals/departures" in w
        for w in warnings
    )


# проверяем WARNING
# при некорректном payload (не словарь)
def test_logging_warning_invalid_payload(monkeypatch, caplog):
    caplog.set_level(logging.WARNING)

    def mock_get(*args, **kwargs):
        return MockResponse(
            json_data="not a dict"
        )

    monkeypatch.setattr("requests.get", mock_get)

    extract_aerodatabox_fids_range_batch(
        airport_code="HKT",
        code_type="IATA",
        start_date="2026-02-19",
        end_date="2026-02-19"
    )

    warnings = [
        r.message
        for r in caplog.records
        if r.levelno == logging.WARNING
    ]

    assert any(
        "Ошибка сети (attempt" in w
        for w in warnings
    )