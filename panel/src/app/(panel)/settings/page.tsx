"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";

import { PriceList } from "@/components/price-list";
import { ServiceAreas } from "@/components/service-areas";
import { SettingsForm } from "@/components/settings-form";
import { Button, Card, EmptyState } from "@/components/ui";
import { api } from "@/lib/client-api";
import type { SettingsDocument } from "@/types/api";

const GROUPS: { value: string; label: string }[] = [
  { value: "dispatch", label: "Dispatch" },
  { value: "pricing", label: "Pricing" },
  { value: "service_areas", label: "Service areas" },
  { value: "drivers", label: "Drivers" },
  { value: "notifications", label: "Notifications" },
  { value: "operational", label: "Operational" },
];

export default function SettingsPage() {
  const [group, setGroup] = useState("dispatch");

  const settings = useQuery({
    queryKey: ["settings"],
    queryFn: () => api<SettingsDocument>("/settings"),
  });

  if (settings.isLoading) return <EmptyState>Loading…</EmptyState>;
  if (settings.isError || !settings.data) return <EmptyState>Could not load settings.</EmptyState>;

  const specs = settings.data.specs.filter((spec) => spec.group === group);

  return (
    <div className="space-y-4">
      <nav className="flex flex-wrap gap-1">
        {GROUPS.map((option) => (
          <Button
            key={option.value}
            size="sm"
            variant={group === option.value ? "primary" : "secondary"}
            onClick={() => setGroup(option.value)}
          >
            {option.label}
          </Button>
        ))}
      </nav>

      <Card title={GROUPS.find((option) => option.value === group)?.label}>
        <SettingsForm specs={specs} values={settings.data.values} />
      </Card>

      {group === "pricing" ? <PriceList /> : null}
      {group === "service_areas" ? <ServiceAreas /> : null}
    </div>
  );
}
