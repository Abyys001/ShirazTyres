/**
 * Hand-maintained mirror of the DRF contract. `npm run generate:types` regenerates
 * src/types/openapi.d.ts from backend/openapi.yaml — use that when you need the full
 * schema; these aliases are what the UI actually consumes.
 */

export type BookingStatus = "received" | "assigned" | "in_progress" | "completed" | "cancelled";
export type BookingIssue = "puncture" | "blowout" | "tyre_damage" | "wheel_change" | "other";
export type BookingSource = "website" | "app" | "panel" | "phone";

export interface StaffUser {
  id: number;
  name: string;
  email: string;
  role: "owner" | "staff";
  is_active: boolean;
  date_joined: string;
}

export interface Vehicle {
  id: number;
  plate: string;
  display_plate: string;
  description: string;
  make: string;
  model: string;
  colour: string;
  fuel_type: string;
  engine_capacity: number | null;
  year_of_manufacture: number | null;
  co2_emissions: number | null;
  tax_status: string;
  tax_due_date: string | null;
  mot_status: string;
  mot_expiry_date: string | null;
  tyre_size_front: string;
  tyre_size_rear: string;
  tyre_load_index: string;
  tyre_speed_rating: string;
  tyre_pressure_front_psi: number | null;
  tyre_pressure_rear_psi: number | null;
  tyre_size_options: string[];
  tyre_source: "api" | "driver" | "staff" | "unknown";
  dvla_fetched_at: string | null;
  tyre_fetched_at: string | null;
  lookup_error: string;
  updated_at: string;
}

export interface BookingStatusEvent {
  id: number;
  from_status: string;
  to_status: string;
  note: string;
  changed_by_name: string;
  created_at: string;
}

export interface Booking {
  id: number;
  reference: string;
  driver_id: number | null;
  vehicle: Vehicle | null;
  plate: string;
  contact_name: string;
  contact_phone: string;
  contact_email: string;
  issue_type: BookingIssue;
  issue_display: string;
  description: string;
  tyre_size: string;
  location_text: string;
  latitude: string | null;
  longitude: string | null;
  status: BookingStatus;
  status_display: string;
  source: BookingSource;
  assigned_to: StaffUser | null;
  internal_notes: string;
  created_at: string;
  updated_at: string;
  assigned_at: string | null;
  completed_at: string | null;
  maps_url: string;
  status_events?: BookingStatusEvent[];
}

export interface Driver {
  id: number;
  name: string;
  phone: string;
  email: string;
  is_phone_verified: boolean;
  is_active: boolean;
  notes: string;
  vehicle_count: number;
  created_at: string;
  updated_at: string;
  last_login_at: string | null;
}

export interface BookingStats {
  received: number;
  assigned: number;
  in_progress: number;
  completed_today: number;
  open_total: number;
}

export interface Paginated<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

export interface ApiErrorBody {
  detail: string;
  errors: Record<string, string[]>;
}

export const STATUS_LABELS: Record<BookingStatus, string> = {
  received: "Received",
  assigned: "Assigned",
  in_progress: "In progress",
  completed: "Completed",
  cancelled: "Cancelled",
};

/** Mirrors Booking.ALLOWED_TRANSITIONS on the server — the API is still the authority. */
export const NEXT_STATUSES: Record<BookingStatus, BookingStatus[]> = {
  received: ["assigned", "in_progress", "cancelled"],
  assigned: ["in_progress", "received", "cancelled"],
  in_progress: ["completed", "cancelled"],
  completed: [],
  cancelled: [],
};
