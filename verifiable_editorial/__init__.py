"""verifiable_editorial — Automated verification & visual-QA court for verifiable PDF publications."""

__version__ = "0.2.0"

from .contrast import audit_contrast
from .coverage import audit_coverage
from .geometry import audit_geometry
from .prose import audit_prose
from .spreads import render_spreads

__all__ = [
    "audit_contrast",
    "audit_coverage",
    "audit_geometry",
    "audit_prose",
    "render_spreads",
    "__version__",
]
