module Generation
  # Stage: storyboard / scene planning (spec §20 steps 7-9).
  class StoryboardJob < BaseJob
    sidekiq_options queue: "storyboard"

    def run(gen_job)
      scenes = Ai::ScenePlannerService.new(project: gen_job.project).call
      gen_job.update!(result: { scene_count: scenes.size })
      GenerationLog.create!(
        project: gen_job.project, generation_job: gen_job, level: "info",
        stage: "storyboard", message: "Planned #{scenes.size} scenes"
      )
    end
  end
end
