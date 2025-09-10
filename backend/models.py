from __future__ import annotations

from datetime import datetime, date
from typing import Optional

from sqlalchemy import (
    BigInteger,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    Index,
    Boolean,
)
from sqlalchemy.orm import declarative_base, relationship, Mapped, mapped_column


Base = declarative_base()


class Event(Base):
    __tablename__ = "events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    year: Mapped[int] = mapped_column(Integer, index=True, nullable=False)
    round: Mapped[int] = mapped_column(Integer, nullable=True)
    location: Mapped[str] = mapped_column(String(100), nullable=True)
    country: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    name: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)

    __table_args__ = (
        UniqueConstraint("year", "name", name="uq_event_year_name"),
    )

    sessions = relationship("Session", back_populates="event", cascade="all, delete-orphan")


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    event_id: Mapped[int] = mapped_column(ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(50), index=True)  # e.g., FP1, Q, R
    date: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    event = relationship("Event", back_populates="sessions")
    laps = relationship("Lap", back_populates="session", cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint("event_id", "type", name="uq_session_event_type"),
    )


class Driver(Base):
    __tablename__ = "drivers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(String(3), index=True)  # three-letter code (Abbreviation)
    number: Mapped[Optional[int]] = mapped_column(Integer, index=True)  # race number
    first_name: Mapped[Optional[str]] = mapped_column(String(100))
    last_name: Mapped[Optional[str]] = mapped_column(String(100))
    team_name: Mapped[Optional[str]] = mapped_column(String(100))
    team_color: Mapped[Optional[str]] = mapped_column(String(10))
    # legacy field for backward-compatibility (kept nullable)
    team: Mapped[Optional[str]] = mapped_column(String(100))

    __table_args__ = (
        UniqueConstraint("code", name="uq_driver_code"),
    )

    laps = relationship("Lap", back_populates="driver")


class Lap(Base):
    __tablename__ = "laps"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("sessions.id", ondelete="CASCADE"), index=True)
    driver_id: Mapped[int] = mapped_column(ForeignKey("drivers.id", ondelete="RESTRICT"), index=True)

    lap_number: Mapped[int] = mapped_column(Integer, index=True)
    lap_time_ms: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    compound: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    position: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    tyre_life: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    track_status: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)

    session = relationship("Session", back_populates="laps")
    driver = relationship("Driver", back_populates="laps")
    telemetries = relationship("Telemetry", back_populates="lap", cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint("session_id", "driver_id", "lap_number", name="uq_lap_unique"),
        Index("ix_laps_session_driver", "session_id", "driver_id"),
    )


class Telemetry(Base):
    __tablename__ = "telemetry"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    lap_id: Mapped[int] = mapped_column(ForeignKey("laps.id", ondelete="CASCADE"), index=True)

    # time-related
    time_s: Mapped[Optional[float]] = mapped_column(Float)
    distance_m: Mapped[Optional[float]] = mapped_column(Float)

    # car data
    speed_kmh: Mapped[Optional[float]] = mapped_column(Float)
    rpm: Mapped[Optional[float]] = mapped_column(Float)
    gear: Mapped[Optional[int]] = mapped_column(Integer)
    throttle: Mapped[Optional[float]] = mapped_column(Float)
    brake: Mapped[Optional[bool]] = mapped_column(Boolean)  # true/false
    drs: Mapped[Optional[int]] = mapped_column(Integer)

    lap = relationship("Lap", back_populates="telemetries")
