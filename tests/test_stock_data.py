import pytest

from stock_data import parse_yahoo_chart


def chart_data(closes, previous_close=None):
    chart = {
        "timestamp": list(range(len(closes))),
        "indicators": {"quote": [{"close": closes}]},
    }
    if previous_close is not None:
        chart["meta"] = {"previousClose": previous_close}
    return {
        "chart": {
            "result": [chart]
        }
    }


def test_parse_yahoo_chart_uses_latest_close_and_direction():
    assert parse_yahoo_chart(chart_data([332.41, 337.0]), "AAPL") == {
        "text": "AAPL: $337.00",
        "status": "up",
    }


@pytest.mark.parametrize(
    ("closes", "status"),
    [([337.0, 332.41], "down"), ([332.41, 332.41], "flat")],
)
def test_parse_yahoo_chart_sets_direction(closes, status):
    assert parse_yahoo_chart(chart_data(closes), "AAPL")["status"] == status


def test_parse_yahoo_chart_compares_live_price_to_previous_close():
    result = parse_yahoo_chart(chart_data([336.95, 337.0], 332.41), "AAPL")

    assert result == {"text": "AAPL: $337.00", "status": "up"}


def test_parse_yahoo_chart_skips_missing_close_values():
    result = parse_yahoo_chart(chart_data([None, 332.41, None, 337.0]), "AAPL")

    assert result == {"text": "AAPL: $337.00", "status": "up"}


def test_parse_yahoo_chart_rejects_empty_data():
    with pytest.raises(ValueError, match="no closing prices"):
        parse_yahoo_chart(chart_data([None, None]), "AAPL")