export const API_BASE_URL = (
  process.env.API_BASE_URL ?? process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000/api/v1"
).replace(/\/$/, "");

export const ACCESS_COOKIE = "st_customer_access";
export const REFRESH_COOKIE = "st_customer_refresh";
