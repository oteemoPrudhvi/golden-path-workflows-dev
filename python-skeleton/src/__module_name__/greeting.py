"""Sample module. Replace it with your package's real code."""


def greet(name: str) -> str:
    """Return a greeting for ``name``."""
    if not name.strip():
        raise ValueError("name must not be empty")
    return f"Hello, {name}!"
