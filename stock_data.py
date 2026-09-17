"""Helpers for turning Yahoo Finance chart responses into ticker records."""


def parse_yahoo_chart(data, symbol):
    """Return display text and direction from a Yahoo chart response."""
    chart = data["chart"]["result"][0]
    previous_close = chart.get("meta", {}).get("previousClose")
    timestamps = chart.get("timestamp", [])
    closes = chart["indicators"]["quote"][0].get("close", [])
    bars = [
        (timestamp, close)
        for timestamp, close in zip(timestamps, closes)
        if close is not None
    ]
    if not bars:
        raise ValueError(f"Yahoo returned no closing prices for {symbol}")

    latest_close = bars[-1][1]
    status = "flat"
    if previous_close is None and len(bars) > 1:
        previous_close = bars[-2][1]
    if previous_close is not None:
        if latest_close > previous_close:
            status = "up"
        elif latest_close < previous_close:
            status = "down"

    return {"text": f"{symbol}: ${latest_close:.2f}", "status": status}