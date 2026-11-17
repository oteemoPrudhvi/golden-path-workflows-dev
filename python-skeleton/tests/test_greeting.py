import pytest

from {{module_name}} import greet


def test_greet() -> None:
    assert greet("Backstage") == "Hello, Backstage!"


def test_greet_rejects_empty_name() -> None:
    with pytest.raises(ValueError):
        greet("  ")
