"use client";

import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@clipify/ui";
import type { CheckVerdict } from "@clipify/types";
import {
  useAcknowledgePreflight,
  useGeneratePreflight,
  usePreflight,
} from "@/lib/api/preflight";
import { useProjectJobs } from "@/lib/api/pipeline";

const LABELS: Record<string, string> = {
  originality: "Originality",
  narrative_value: "Narrative value",
  repetition_risk: "Repetition risk",
  asset_provenance: "Asset provenance",
  reuse_risk: "Reuse risk",
  copyright_license: "Copyright / license",
  advertiser_suitability: "Advertiser suitability",
};

const TONE: Record<CheckVerdict, Parameters<typeof Badge>[0]["tone"]> = {
  pass: "success",
  warn: "warning",
  review: "info",
};

export function PreflightCard({ projectId }: { projectId: string }) {
  const { data: report } = usePreflight(projectId);
  const { data: jobs } = useProjectJobs(projectId);
  const generate = useGeneratePreflight(projectId);
  const acknowledge = useAcknowledgePreflight(projectId);

  const running = jobs?.some((j) => j.stage === "preflight" && j.active) ?? false;

  return (
    <Card>
      <CardHeader>
        <CardTitle>YouTube preflight</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <Button
            size="sm"
            disabled={running || generate.isPending}
            onClick={() => generate.mutate()}
          >
            {running ? "Checking…" : report ? "Re-run preflight" : "Run preflight"}
          </Button>
          {report && (
            <Badge tone={report.status === "ready" ? "success" : "warning"}>
              {report.status === "ready" ? "Ready" : "Review required"}
            </Badge>
          )}
        </div>

        {report && (
          <>
            <ul className="flex flex-col gap-1.5 text-sm">
              {Object.entries(report.checks).map(([key, verdict]) => (
                <li key={key} className="flex items-center justify-between">
                  <span>{LABELS[key] ?? key}</span>
                  <Badge tone={TONE[verdict]}>{verdict}</Badge>
                </li>
              ))}
              <li className="flex items-center justify-between">
                <span>AI disclosure</span>
                <Badge tone={report.ai_disclosure === "not_required" ? "success" : "info"}>
                  {report.ai_disclosure.replace(/_/g, " ")}
                </Badge>
              </li>
            </ul>

            {report.warnings.length > 0 && (
              <ul className="flex flex-col gap-1 rounded-md bg-surface-2 p-3 text-xs text-muted">
                {report.warnings.map((w, i) => (
                  <li key={i}>
                    <span className="font-medium">{LABELS[w.check] ?? w.check}:</span> {w.message}
                  </li>
                ))}
              </ul>
            )}

            <p className="text-xs text-muted">{report.disclaimer}</p>

            {report.status === "review_required" && !report.acknowledged_at && (
              <Button
                size="sm"
                variant="outline"
                disabled={acknowledge.isPending}
                onClick={() => acknowledge.mutate()}
              >
                Acknowledge warnings
              </Button>
            )}
            {report.acknowledged_at && (
              <p className="text-xs text-success">Warnings acknowledged.</p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
