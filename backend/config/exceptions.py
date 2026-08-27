from rest_framework.views import exception_handler


def api_exception_handler(exc, context):
    """Flatten DRF errors into {"detail": ..., "errors": {...}} so clients parse one shape."""
    response = exception_handler(exc, context)
    if response is None:
        return None

    data = response.data
    if isinstance(data, dict) and "detail" in data:
        response.data = {"detail": data["detail"], "errors": {}}
    elif isinstance(data, dict):
        response.data = {"detail": "Validation failed.", "errors": data}
    else:
        response.data = {"detail": "Request failed.", "errors": {"non_field_errors": data}}
    return response
