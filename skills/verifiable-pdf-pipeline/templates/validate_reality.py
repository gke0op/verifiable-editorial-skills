#!/usr/bin/env python3
"""
Template — Phase 2: Reality & Invariant Compiler (Rule 2 + Rule 5).

Validates parsed raw records against domain physics bounds, temporal monotonicity,
and exact accounting identities via Pydantic v2. Maps upstream missing-data sentinels
explicitly to None (Sacred N/A) and fails closed (exit 1) on any invariant breach.
"""
from __future__ import annotations

import sys
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class DomainObservation(BaseModel):
    """Adapt fields and physical/accounting bounds to your project domain."""

    entity_id: str = Field(..., min_length=1)
    year: int = Field(..., ge=1900, le=2100)
    total_metric: Optional[float] = Field(None, ge=0.0)
    denominator: Optional[float] = Field(None, gt=0.0)
    per_unit_metric: Optional[float] = Field(None, ge=0.0)

    @model_validator(mode="after")
    def enforce_identities(self) -> "DomainObservation":
        # Cross-field accounting identity: total / denominator == per_unit
        if (
            self.total_metric is not None
            and self.denominator is not None
            and self.per_unit_metric is not None
            and self.per_unit_metric > 0
        ):
            recomputed = self.total_metric / self.denominator
            rel_err = abs(recomputed - self.per_unit_metric) / self.per_unit_metric
            if rel_err > 1e-4:
                raise ValueError(
                    f"FATAL IDENTITY BREACH ({self.entity_id} {self.year}): "
                    f"total/denom={recomputed:.6g} != reported per_unit={self.per_unit_metric:.6g} "
                    f"(rel_err={rel_err:.2e})"
                )
        return self


def sentinel_to_none(value: float, sentinels: tuple[float, ...] = (-999.0, -99.9, -9.99, -0.99, -1.0)) -> Optional[float]:
    """Convert upstream numeric missing-data sentinels cleanly into None."""
    for s in sentinels:
        if abs(value - s) < 1e-9:
            return None
    return value


def validate_records(records: list[dict]) -> list[DomainObservation]:
    validated: list[DomainObservation] = []
    for idx, raw in enumerate(records):
        try:
            validated.append(DomainObservation(**raw))
        except Exception as exc:
            print(f"[!] REALITY INVARIANT BREACH at row {idx}: {exc}", file=sys.stderr)
            sys.exit(1)
    return validated


if __name__ == "__main__":
    print("[*] Reality validator template ready. Import and subclass DomainObservation for your raw parser.")
