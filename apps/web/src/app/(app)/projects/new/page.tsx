"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button, Card, CardContent, Input, Label, Textarea } from "@clipify/ui";
import type { ProjectFormat, VisualStyle } from "@clipify/types";
import { useCreateProject } from "@/lib/api/projects";
import { useTemplates } from "@/lib/api/templates";
import { FORMATS, VISUAL_STYLES } from "@/lib/constants";

export default function NewProjectPage() {
  const router = useRouter();
  const create = useCreateProject();
  const { data: templates } = useTemplates();

  const [form, setForm] = useState({
    title: "",
    topic: "",
    format: "youtube_long" as ProjectFormat,
    visual_style: "cinematic" as VisualStyle,
    target_duration_seconds: 120,
    template_id: "",
  });

  return (
    <div className="mx-auto max-w-xl">
      <h1 className="mb-6 text-2xl font-semibold">New project</h1>
      <Card>
        <CardContent className="pt-6">
          <form
            className="flex flex-col gap-4"
            onSubmit={(e) => {
              e.preventDefault();
              create.mutate(
                {
                  title: form.title,
                  topic: form.topic || undefined,
                  format: form.format,
                  visual_style: form.visual_style,
                  target_duration_seconds: Number(form.target_duration_seconds),
                  template_id: form.template_id || undefined,
                },
                { onSuccess: (project) => router.push(`/projects/${project.id}`) },
              );
            }}
          >
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="title">Title</Label>
              <Input
                id="title"
                required
                value={form.title}
                onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
              />
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="topic">Topic or script</Label>
              <Textarea
                id="topic"
                rows={5}
                placeholder="Paste a script, or describe the topic you want a video about."
                value={form.topic}
                onChange={(e) => setForm((f) => ({ ...f, topic: e.target.value }))}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="format">Format</Label>
                <select
                  id="format"
                  className="h-10 rounded-md border border-border bg-surface-1 px-3 text-sm"
                  value={form.format}
                  onChange={(e) =>
                    setForm((f) => ({ ...f, format: e.target.value as ProjectFormat }))
                  }
                >
                  {FORMATS.map((f) => (
                    <option key={f.value} value={f.value}>
                      {f.label}
                    </option>
                  ))}
                </select>
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor="duration">Target length (seconds)</Label>
                <Input
                  id="duration"
                  type="number"
                  min={15}
                  max={1800}
                  value={form.target_duration_seconds}
                  onChange={(e) =>
                    setForm((f) => ({ ...f, target_duration_seconds: Number(e.target.value) }))
                  }
                />
              </div>
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="visual_style">Visual style</Label>
              <select
                id="visual_style"
                className="h-10 rounded-md border border-border bg-surface-1 px-3 text-sm"
                value={form.visual_style}
                onChange={(e) =>
                  setForm((f) => ({ ...f, visual_style: e.target.value as VisualStyle }))
                }
              >
                {VISUAL_STYLES.map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </select>
              <p className="text-xs text-muted">
                Applied to every generated image. Match it to your topic — e.g. “Wildlife
                documentary” for nature videos.
              </p>
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="template">Template</Label>
              <select
                id="template"
                className="h-10 rounded-md border border-border bg-surface-1 px-3 text-sm"
                value={form.template_id}
                onChange={(e) => setForm((f) => ({ ...f, template_id: e.target.value }))}
              >
                <option value="">No template</option>
                {templates?.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                  </option>
                ))}
              </select>
            </div>

            {create.isError && (
              <p className="text-sm text-danger">{(create.error as Error).message}</p>
            )}

            <div className="flex gap-3">
              <Button type="submit" disabled={create.isPending}>
                {create.isPending ? "Creating…" : "Create project"}
              </Button>
              <Button type="button" variant="ghost" onClick={() => router.back()}>
                Cancel
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
