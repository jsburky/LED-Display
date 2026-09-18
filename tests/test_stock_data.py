import pytest

from datetime import datetime, timezone

from stock_data import cache_entry_is_stale, parse_yahoo_chart


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


def test_cache_entry_stale_detection():
    now = datetime(2026, 9, 17, 12, tzinfo=timezone.utc)

    assert cache_entry_is_stale("2026-09-17T11:44:59+00:00", now, 900)
    assert not cache_entry_is_stale("2026-09-17T11:45:01+00:00", now, 900)
    assert cache_entry_is_stale(None, now, 900)