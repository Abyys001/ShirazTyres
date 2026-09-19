"""Channel group names, in one place so a typo cannot silently route nothing anywhere."""

PANEL = "panel"

#: Every technician on the app at once, for the open board they all share.
#: Their own job and offer traffic still goes to :func:`driver_group`.
DRIVERS = "drivers"


def customer_group(customer_id: int) -> str:
    return f"customer.{customer_id}"


def driver_group(driver_id: int) -> str:
    return f"driver.{driver_id}"


def job_group(job_id: int) -> str:
    return f"job.{job_id}"
