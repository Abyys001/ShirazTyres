"""Channel group names, in one place so a typo cannot silently route nothing anywhere."""

PANEL = "panel"


def customer_group(customer_id: int) -> str:
    return f"customer.{customer_id}"


def driver_group(driver_id: int) -> str:
    return f"driver.{driver_id}"


def job_group(job_id: int) -> str:
    return f"job.{job_id}"
