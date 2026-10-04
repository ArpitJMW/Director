module Generation
  # Stage: scene planning + shot planning (planning-doc §7). Plans meaningful
  # story-beat scenes, then subdivides the longer ones into shots (one batched
  # LLM call) so nothing sits static on screen. Kept as one stage so the
  # orchestrator and UI are unchanged.
  class StoryboardJob < BaseJob
    sidekiq_options queue: "storyboard"

    def run(gen_job)
      project = gen_job.project

      look_for(project, gen_job)
      scenes = Ai::ScenePlannerService.new(project: project).call

      shot_count = 0
      begin
        shot_count = Ai::ShotPlanner.new(project: project).call.size
      rescue => e
        # A failed shot plan is not fatal — scenes render at scene level.
        GenerationLog.create!(
          project: project, generation_job: gen_job, level: "warn",
          stage: "storyboard", message: "shot planning failed: #{e.message}"
        )
      end

      gen_job.update!(result: { scene_count: scenes.size, shot_count: shot_count })
      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info",
        stage: "storyboard", message: "Planned #{scenes.size} scenes, #{shot_count} shots"
      )
    end

    private

    # Task 6.2 Part 2: the project look. A failure is logged and planning goes on.
    def look_for(project, gen_job)
      Ai::LookService.new(project: project).call
    rescue => e
      GenerationLog.create!(project: project, generation_job: gen_job, level: "warn", stage: "storyboard",
                            message: "look unavailable (#{e.message.to_s.truncate(160)}); planning without a look")
    end
  end
end
