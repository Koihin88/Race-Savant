from __future__ import annotations

from typing import Optional
import pandas as pd


def coalesce_attr(obj, *names):
    for n in names:
        if isinstance(obj, dict) and n in obj:
            return obj[n]
        if hasattr(obj, n):
            return getattr(obj, n)
    return None


def to_ms(val) -> Optional[int]:
    if val is None or pd.isna(val):
        return None
    td = pd.to_timedelta(val)
    return int(td.total_seconds() * 1000)


def to_int(val) -> Optional[int]:
    if val is None or (isinstance(val, float) and pd.isna(val)) or (isinstance(val, str) and val == ""):
        return None
    try:
        return int(val)
    except Exception:
        return None


def to_float(val) -> Optional[float]:
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return None
    try:
        return float(val)
    except Exception:
        return None


def timedelta_to_s(val) -> Optional[float]:
    if val is None or pd.isna(val):
        return None
    td = pd.to_timedelta(val)
    return float(td.total_seconds())
